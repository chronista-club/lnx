import Foundation
import Testing
@testable import LnxCreare

/// サーバ名ごとの pin（leaf 証明書 DER）の置き場
@Suite("PinStore")
struct PinStoreTests {
    @Test("memory: 保存・読み出し・上書き・削除")
    func memory() {
        let store = MemoryPinStore()
        exercise(store)
    }

    @Test("Keychain: 保存・読み出し・上書き・削除")
    func keychain() {
        // 本物の pin と混ざらないよう、試験ごとに service を分ける
        let store = KeychainPinStore(service: "club.chronista.lnx.creare.pin.test.\(UUID().uuidString)")
        exercise(store)
    }

    private func exercise(_ store: some PinStore) {
        #expect(store.certificate(for: "lnx-mac") == nil)
        store.save(Data([1, 2, 3]), for: "lnx-mac")
        #expect(store.certificate(for: "lnx-mac") == Data([1, 2, 3]))
        #expect(store.certificate(for: "other") == nil)
        store.save(Data([4, 5]), for: "lnx-mac")
        #expect(store.certificate(for: "lnx-mac") == Data([4, 5]))
        store.remove(for: "lnx-mac")
        #expect(store.certificate(for: "lnx-mac") == nil)
    }
}
