import Foundation

protocol Loggable {
    func log(_ message: String)
}

extension Loggable {
    func log(_ message: String) {
        Log.shared.info("\(String(describing: type(of: self))): \(message)")
    }

    func logDebug(_ message: String) {
        Log.shared.debug("\(String(describing: type(of: self))): \(message)")
    }

    func logError(_ message: String) {
        Log.shared.error("\(String(describing: type(of: self))): \(message)")
    }

    func logWarning(_ message: String) {
        Log.shared.warning("\(String(describing: type(of: self))): \(message)")
    }
}