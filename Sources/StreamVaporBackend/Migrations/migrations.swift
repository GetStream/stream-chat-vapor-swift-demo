import Fluent
import Vapor

func migrations(_ app: Application) throws {
    app.migrations.add(User.CreateUser())
    app.migrations.add(UserToken.CreateUserToken())
    
    try app.autoMigrate().wait()
}
