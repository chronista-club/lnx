import Foundation
import Network
import Testing
@testable import LnxCreare

/// Bonjour で見つけた先の選び方
@Suite("LnxFinder")
struct LnxFinderTests {
    let a = LinkTarget.host("192.168.0.2", port: 12730, name: "lnx-a")
    let b = LinkTarget.host("192.168.0.3", port: 12730, name: "lnx-b")

    @Test("ペアリング済みの先を、見つかった順より優先する")
    func prefersPaired() {
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-b")
        #expect(LnxFinder.choose(from: [a, b], pins: pins) == b)
    }

    @Test("pin が無くても、まだ見つかっている今の先を手放さない（解除したあと別のサーバへ飛ばない）")
    func keepsCurrent() {
        let pins = MemoryPinStore()
        #expect(LnxFinder.choose(from: [b, a], pins: pins, current: a) == a)
        // ペアリング済みの先があればそちら
        pins.save(Data([1]), for: "lnx-b")
        #expect(LnxFinder.choose(from: [b, a], pins: pins, current: a) == b)
        // 今の先がもう見つからなければ先頭
        #expect(LnxFinder.choose(from: [b], pins: MemoryPinStore(), current: a) == b)
    }

    @Test("今の先は名前で照合する（解き直しでアドレスだけ変わっても、別のサーバへ飛ばない）")
    func keepsCurrentByName() {
        let aMoved = LinkTarget.host("192.168.0.9", port: 12730, name: "lnx-a")
        #expect(LnxFinder.choose(from: [b, aMoved], pins: MemoryPinStore(), current: a) == aMoved)
    }

    @Test("ペアリング済みが無ければ先頭")
    func fallsBackToFirst() {
        #expect(LnxFinder.choose(from: [a, b], pins: MemoryPinStore()) == a)
        #expect(LnxFinder.choose(from: [], pins: MemoryPinStore()) == nil)
    }

    @Test("Bonjour の service endpoint からインスタンス名を取る")
    func serviceName() {
        let service = NWEndpoint.service(name: "lnx-mac", type: "_lnx._udp", domain: "local.", interface: nil)
        #expect(LnxFinder.serviceName(service) == "lnx-mac")
        #expect(LnxFinder.serviceName(.hostPort(host: "::1", port: 12730)) == nil)
    }

    // MARK: - サーバの名乗り（pin の鍵）

    let service = NWEndpoint.service(name: "lnx-mac (2)", type: "_lnx._udp", domain: "local.", interface: nil)

    @Test("TXT の name があればそれを名乗りにする（Bonjour が「(2)」に改名しても QR の name と合う）")
    func nameFromTXT() {
        let txt = NWTXTRecord(["name": "lnx-mac", "version": "0.1.0", "protocol": "unison"])
        #expect(LnxFinder.serverName(service, metadata: .bonjour(txt)) == "lnx-mac")
    }

    @Test("TXT に name が無い・空なら、インスタンス名に倒れる（#33 より前のサーバ）")
    func nameFallsBackToInstance() {
        #expect(LnxFinder.serverName(service, metadata: .bonjour(NWTXTRecord(["version": "0.1.0"]))) == "lnx-mac (2)")
        #expect(LnxFinder.serverName(service, metadata: .bonjour(NWTXTRecord(["name": ""]))) == "lnx-mac (2)")
        #expect(LnxFinder.serverName(service, metadata: .none) == "lnx-mac (2)")
    }

    // MARK: - 見つかった先の帳簿

    let svcA = NWEndpoint.service(name: "lnx-a", type: "_lnx._udp", domain: "local.", interface: nil)
    let svcB = NWEndpoint.service(name: "lnx-b", type: "_lnx._udp", domain: "local.", interface: nil)

    @Test("解けた先は IPv4 を前に並べる")
    func ledgerOrdersIPv4First() {
        var ledger = FoundTargets()
        ledger.set(.host("fe80::1%en0", port: 12730, name: "lnx-a"), for: svcA)
        ledger.set(.host("192.168.0.3", port: 12730, name: "lnx-b"), for: svcB)
        #expect(ledger.targets == [.host("192.168.0.3", port: 12730, name: "lnx-b"), .host("fe80::1%en0", port: 12730, name: "lnx-a")])
    }

    @Test("同じ service が解け直したら、古いアドレスは置き換わる")
    func ledgerReplacesAddress() {
        var ledger = FoundTargets()
        ledger.set(.host("192.168.0.2", port: 12730, name: "lnx-a"), for: svcA)
        ledger.set(.host("192.168.0.9", port: 12730, name: "lnx-a"), for: svcA)
        #expect(ledger.targets == [.host("192.168.0.9", port: 12730, name: "lnx-a")])
    }

    @Test("Bonjour から消えた service の先は忘れる")
    func ledgerForgetsLost() {
        var ledger = FoundTargets()
        ledger.set(.host("192.168.0.2", port: 12730, name: "lnx-a"), for: svcA)
        ledger.set(.host("192.168.0.3", port: 12730, name: "lnx-b"), for: svcB)
        ledger.retain(only: [svcB])
        #expect(ledger.targets == [.host("192.168.0.3", port: 12730, name: "lnx-b")])
        #expect(!ledger.contains(svcA))
        #expect(ledger.contains(svcB))
    }

    // MARK: - 解き直し

    @Test("Bonjour が変わったら、解けている先も解き直す（同じ名前のまま IP だけ変わる。USB を抜いた実例 2026-11-23）")
    func reResolvesResolvedOnChange() {
        // svcA は解決済み（帳簿にある）、svcB は解決中
        let toResolve = LnxFinder.endpointsToResolve(advertised: [svcA, svcB], resolving: [svcB])
        #expect(toResolve == [svcA])
    }

    @Test("解決中の先は二重に解かない")
    func doesNotDoubleResolve() {
        #expect(LnxFinder.endpointsToResolve(advertised: [svcA], resolving: [svcA]).isEmpty)
    }
}
