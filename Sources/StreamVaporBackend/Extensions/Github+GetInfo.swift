import ImperialGitHub
import Vapor

struct GitHubUserInfo: Content {
    let name: String
    let login: String
}

extension GitHub {
    static func getUser(on request: Request) async throws -> GitHubUserInfo {
        var headers = HTTPHeaders()
        try headers.add(name: .authorization, value: "token \(request.accessToken())")
        headers.add(name: .userAgent, value: "vapor")
        
        let githubUserAPIURL: URI = "https://api.github.com/user"
        let response = try await request.client.get(githubUserAPIURL, headers: headers)
        guard response.status == .ok else {
            if response.status == .unauthorized {
                throw Abort.redirect(to: "/login-github")
            } else {
                throw Abort(.internalServerError)
            }
        }
        return try response.content.decode(GitHubUserInfo.self)
    }
}
