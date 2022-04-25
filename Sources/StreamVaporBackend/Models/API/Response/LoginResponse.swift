import Vapor

struct LoginResponse: Content {
    let apiToken: UserToken
}
