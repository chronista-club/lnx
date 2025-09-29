import Foundation

class User: Loggable {
    let id: UUID
    var name: String
    var email: String?

    init(name: String = "Default User", email: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        log("User created: \(name)")
    }

    func updateName(_ newName: String) {
        let oldName = name
        name = newName
        log("User name updated from \(oldName) to \(newName)")
    }
}