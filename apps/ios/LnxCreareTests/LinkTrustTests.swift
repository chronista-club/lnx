import Foundation
import Testing
import UnisonClient
@testable import LnxCreare

/// つなぐ先ごとの信頼の決め方 — 同じ機械は検証を飛ばす、LAN はペアリングした証明書に pin
@Suite("LinkTrust")
struct LinkTrustTests {
    let der = Data([0x30, 0x82, 0x01])

    @Test("同じ機械（localhost）は skipVerify")
    func localDaemon() {
        let pins = MemoryPinStore()
        #expect(LinkTrust.decide(for: .localDaemon(port: 1), pins: pins) == .connect(.skipVerify))
    }

    @Test("ペアリング済みの LAN サーバはその証明書に pin")
    func pairedHost() {
        let pins = MemoryPinStore()
        pins.save(der, for: "lnx-mac")
        let target = LinkTarget.host("192.168.0.2", port: 12730, name: "lnx-mac")
        #expect(LinkTrust.decide(for: target, pins: pins) == .connect(.pinned(der)))
    }

    @Test("ペアリングしていない LAN サーバにはつながず、ペアリングを求める")
    func unpairedHost() {
        let pins = MemoryPinStore()
        pins.save(der, for: "someone-else")
        let target = LinkTarget.host("192.168.0.2", port: 12730, name: "lnx-mac")
        #expect(LinkTrust.decide(for: target, pins: pins) == .needsPairing(serverName: "lnx-mac"))
    }

    @Test("名前の分からない LAN サーバもペアリングを求める")
    func namelessHost() {
        let pins = MemoryPinStore()
        #expect(LinkTrust.decide(for: .host("192.168.0.2", port: 12730), pins: pins) == .needsPairing(serverName: nil))
    }
}
