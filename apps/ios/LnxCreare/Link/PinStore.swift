import Foundation
import Security
import Synchronization

/// サーバ名ごとの pin（leaf 証明書 DER）の置き場
protocol PinStore: Sendable {
    func certificate(for serverName: String) -> Data?
    func save(_ certificate: Data, for serverName: String)
    func remove(for serverName: String)
}

/// 試験用。プロセスが終われば消える
final class MemoryPinStore: PinStore {
    private let pins = Mutex<[String: Data]>([:])

    func certificate(for serverName: String) -> Data? { pins.withLock { $0[serverName] } }
    func save(_ certificate: Data, for serverName: String) { pins.withLock { $0[serverName] = certificate } }
    func remove(for serverName: String) { _ = pins.withLock { $0.removeValue(forKey: serverName) } }
}

/// 実物。Keychain の generic password（service 固定、account = サーバ名）
struct KeychainPinStore: PinStore {
    var service = "club.chronista.lnx.creare.pin"

    func certificate(for serverName: String) -> Data? {
        var query = baseQuery(serverName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ certificate: Data, for serverName: String) {
        remove(for: serverName)
        var item = baseQuery(serverName)
        item[kSecValueData as String] = certificate
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { LinkLog.note("pin を保存できない: \(serverName) OSStatus \(status)") }
    }

    func remove(for serverName: String) {
        SecItemDelete(baseQuery(serverName) as CFDictionary)
    }

    private func baseQuery(_ serverName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverName,
        ]
    }
}
