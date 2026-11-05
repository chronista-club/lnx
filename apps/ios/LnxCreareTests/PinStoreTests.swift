import Foundation
import Synchronization
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

    @Test("cache: 保存・読み出し・上書き・削除（下の置き場と同じ振る舞い）")
    func cached() {
        exercise(CachedPinStore(MemoryPinStore()))
    }

    @Test("cache: 同じ名前は一度しか下の置き場を読まない（無いことも覚える）")
    func cacheReadsOnce() {
        let base = CountingPinStore()
        base.save(Data([1]), for: "lnx-mac")
        let store = CachedPinStore(base)
        for _ in 0..<5 {
            #expect(store.certificate(for: "lnx-mac") == Data([1]))
            #expect(store.certificate(for: "other") == nil)
        }
        #expect(base.reads == 2)
    }

    @Test("cache: 保存・削除は下の置き場にも書く")
    func cacheWritesThrough() {
        let base = MemoryPinStore()
        let store = CachedPinStore(base)
        store.save(Data([3]), for: "lnx-mac")
        #expect(base.certificate(for: "lnx-mac") == Data([3]))
        store.remove(for: "lnx-mac")
        #expect(base.certificate(for: "lnx-mac") == nil)
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

/// 読み出しを数える置き場（cache の試験用）
final class CountingPinStore: PinStore {
    private let base = MemoryPinStore()
    private let count = Mutex(0)
    var reads: Int { count.withLock { $0 } }

    func certificate(for serverName: String) -> Data? {
        count.withLock { $0 += 1 }
        return base.certificate(for: serverName)
    }
    func save(_ certificate: Data, for serverName: String) { base.save(certificate, for: serverName) }
    func remove(for serverName: String) { base.remove(for: serverName) }
}
