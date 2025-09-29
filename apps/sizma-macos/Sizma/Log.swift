import Foundation

final class Log {
    nonisolated(unsafe) static let shared = Log()

    private init() {}

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        print("🔍 DEBUG [\(extractFileName(file)):\(line)] \(function) - \(message)")
        #endif
    }

    func info(_ message: String) {
        print("ℹ️ INFO: \(message)")
    }

    func warning(_ message: String) {
        print("⚠️ WARNING: \(message)")
    }

    func error(_ message: String) {
        print("❌ ERROR: \(message)")
    }

    private func extractFileName(_ path: String) -> String {
        return URL(fileURLWithPath: path).lastPathComponent
    }
}