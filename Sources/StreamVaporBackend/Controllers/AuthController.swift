import Vapor
import Fluent
import ImperialGoogle
import ImperialGitHub
import JWT

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let authRoutes = routes.grouped("auth")
        authRoutes.post("register", use: registerHandler)
        authRoutes.post("siwa", use: signInWithAppleHandler)
        
        let basicAuthRoutes = authRoutes.grouped(User.authenticator(), User.guardMiddleware())
        basicAuthRoutes.post("login", use: loginHandler)
        
        if let googleCallbackURL = Environment.get("GOOGLE_CALLBACK_URL") {
            try routes.oAuth(from: Google.self, authenticate: "login-google", callback: googleCallbackURL, scope: ["profile", "email"], completion: processGoogleLogin)
            routes.get("iOS", "login-google", use: iOSGoogleLogin)
        }
        
        if let githubCallbackURL = Environment.get("GITHUB_CALLBACK_URL") {
            try routes.oAuth(from: GitHub.self, authenticate: "login-github", callback: githubCallbackURL, completion: processGithubLogin)
            routes.get("iOS", "login-github", use: iOSGithubLogin)
        }
    }
    
    func registerHandler(_ req: Request) async throws -> LoginResponse {
        try CreateUserData.validate(content: req)

        let data = try req.content.decode(CreateUserData.self)
        let passwordHash = try await req.password.async.hash(data.password)
        let user = User(name: data.name, email: data.email, username: data.username, passwordHash: passwordHash, siwaID: nil)
        do {
            try await user.create(on: req.db)
        } catch {
            if let error = error as? DatabaseError, error.isConstraintFailure {
                throw Abort(.badRequest, reason: "A user with that email already exists")
            } else {
                throw error
            }
        }
        return try await createLoginResponse(for: user, on: req)
    }

    // Uses basic authentication to provide an actual bearer token
    func loginHandler(_ req: Request) async throws -> LoginResponse {
        let user = try req.auth.require(User.self)
        return try await createLoginResponse(for: user, on: req)
    }

    func signInWithAppleHandler(_ req: Request) async throws -> LoginResponse {
        let data = try req.content.decode(SignInWithAppleToken.self)
        guard let appIdentifier = Environment.get("IOS_APPLICATION_IDENTIFIER") else {
            throw Abort(.internalServerError)
        }
        let siwaToken = try await req.jwt.apple.verify(data.token, applicationIdentifier: appIdentifier)
        let user: User
        if let foundUser = try await User.query(on: req.db).filter(\.$siwaID == siwaToken.subject.value).first() {
            user = foundUser
        } else {
            guard let email = siwaToken.email, let name = data.name else {
                throw Abort(.badRequest)
            }
            // Set the password t oa secure random value. This won't be run through BCrypt so can't be used to log in anyway
            // The username is restricted to certain characters in Stream's backend
            let username = data.username ?? email.replacingOccurrences(of: "@", with: "-")
            user = User(name: name, email: email, username: username, passwordHash: [UInt8].random(count: 32).base64, siwaID: siwaToken.subject.value)
            try await user.create(on: req.db)
        }
        return try await createLoginResponse(for: user, on: req)
    }
    
    // MARK: - Helpers
    func createLoginResponse(for user: User, on req: Request) async throws -> LoginResponse {
        let token = try user.generateToken()
        try await token.create(on: req.db)
        return LoginResponse(apiToken: token)
    }
    
    // MARK: - OAuth
    func processGoogleLogin(request: Request, token: String) throws -> EventLoopFuture<ResponseEncodable> {
        request.eventLoop.performWithTask {
            try await processGoogleLoginAsync(request: request, token: token)
        }
    }
    
    func processGoogleLoginAsync(request: Request, token: String) async throws -> ResponseEncodable {
        let userInfo = try await Google.getUser(on: request)
        let foundUser = try await User.query(on: request.db).filter(\.$email == userInfo.email).first()
        guard let existingUser = foundUser else {
            let username = userInfo.email.replacingOccurrences(of: "@", with: "-")
            let user = User(name: userInfo.name, email: userInfo.email, username: username, passwordHash: [UInt8].random(count: 32).base64, siwaID: nil)
            try await user.save(on: request.db)
            request.session.authenticate(user)
            return try await generateRedirect(on: request, for: user)
        }
        request.session.authenticate(existingUser)
        return try await generateRedirect(on: request, for: existingUser)
    }
    
    func processGithubLogin(request: Request, token: String) throws -> EventLoopFuture<ResponseEncodable> {
        request.eventLoop.performWithTask {
            try await processGitHubLoginAsync(request: request, token: token)
        }
    }
    
    func processGitHubLoginAsync(request: Request, token: String) async throws -> ResponseEncodable {
        let userInfo = try await GitHub.getUser(on: request)
        let foundUser = try await User.query(on: request.db).filter(\.$username == userInfo.login).first()
        guard let existingUser = foundUser else {
            let username = userInfo.login.replacingOccurrences(of: "@", with: "-")
            let user = User(name: userInfo.name, email: userInfo.login, username: username, passwordHash: [UInt8].random(count: 32).base64, siwaID: nil)
            try await user.save(on: request.db)
            request.session.authenticate(user)
            return try await generateRedirect(on: request, for: user)
        }
        request.session.authenticate(existingUser)
        return try await generateRedirect(on: request, for: existingUser)
      }
    
    func iOSGoogleLogin(_ req: Request) -> Response {
        return req.redirect(to: "/login-google")
    }
    
    func iOSGithubLogin(_ req: Request) -> Response {
        return req.redirect(to: "/login-github")
      }
    
    func generateRedirect(on req: Request, for user: User) async throws -> ResponseEncodable {
        let token = try user.generateToken()
        try await token.save(on: req.db)
        let redirectURL = "streamVapor://auth?token=\(token.value)"
        let streamToken = try req.stream.createToken(id: user.username)
        return req.redirect(to: redirectURL)
    }
}
