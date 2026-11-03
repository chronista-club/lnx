import Foundation
import Testing
@testable import LnxCreare

/// wire の形は crates/lnx-server/schemas/lnx.kdl が正。snake_case のまま読み書きできること
@Suite("LnxProtocol coding")
struct LnxProtocolCodingTests {
    @Test("Heartbeat は seq / uptime_ms")
    func heartbeat() throws {
        let data = Data(#"{"seq": 7, "uptime_ms": 1234}"#.utf8)
        let heartbeat = try JSONDecoder().decode(Heartbeat.self, from: data)
        #expect(heartbeat == Heartbeat(seq: 7, uptimeMs: 1234))
    }

    @Test("Welcome は server_name / server_version / server_time_ms")
    func welcome() throws {
        let data = Data(#"{"server_name":"lnx-mac","server_version":"0.1.0","server_time_ms":1762160000000}"#.utf8)
        let welcome = try JSONDecoder().decode(Welcome.self, from: data)
        #expect(welcome.serverName == "lnx-mac")
        #expect(welcome.serverVersion == "0.1.0")
        #expect(welcome.serverTimeMs == 1_762_160_000_000)
    }

    @Test("Hello は client / client_version で送る")
    func hello() throws {
        let data = try JSONEncoder().encode(Hello(client: "lnx creare", clientVersion: "0.1.0"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["client"] as? String == "lnx creare")
        #expect(object?["client_version"] as? String == "0.1.0")
        #expect(Hello.method == "Hello")
    }

    @Test("RegistryChanged / ServerList の servers は RemoteServer の配列")
    func registry() throws {
        let json = #"{"servers":[{"id":"ladyland.field","name":"Ladyland Field","kind":"field","host":"mako.local","port":7879}]}"#
        let changed = try JSONDecoder().decode(RegistryChanged.self, from: Data(json.utf8))
        let list = try JSONDecoder().decode(ServerList.self, from: Data(json.utf8))
        let expected = RemoteServer(id: "ladyland.field", name: "Ladyland Field", kind: "field", host: "mako.local", port: 7879)
        #expect(changed.servers == [expected])
        #expect(list.servers == [expected])
        #expect(ListServers.method == "List")
    }

    @Test("endpointLabel は host:port を桁区切りなしで出す")
    func endpointLabel() {
        let server = RemoteServer(id: "x", name: "X", kind: "field", host: "localhost", port: 7879)
        #expect(server.endpointLabel == "localhost:7879")
    }

    @Test("channel 名は schema と同じ")
    func channelNames() {
        #expect(SessionChannel.name == "session")
        #expect(RegistryChannel.name == "registry")
    }
}
