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
}
