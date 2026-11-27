import Foundation
import Testing
@testable import LnxClient

private let sampleSnapshotJSON = #"""
{
  "sequence": 1,
  "protocol_version": 1,
  "server_epoch": "boot",
  "session_id": "a",
  "service": {
    "version": "0.1.0-alpha3",
    "executable": "/Applications/LnxCreare.app/Contents/MacOS/lnx-server"
  },
  "gears": [
    {
      "gear_id": "nanokontrol",
      "profile_id": "nanokontrol",
      "name": "nanoKONTROL2",
      "present": true,
      "assignment": { "client_id": "ladyland", "revision": 1, "expected": true },
      "phase": "active",
      "lease": { "session_id": "a", "token": "boot:1" },
      "releasing_to": null,
      "controls": [],
      "native_ports": {
        "inputs": ["Lnx/ladyland/boot:1 | nanoKONTROL2 SLIDER/KNOB"],
        "outputs": []
      },
      "error": null
    },
    {
      "gear_id": "maru",
      "profile_id": "maru",
      "name": "MARU01",
      "present": true,
      "assignment": { "client_id": null, "revision": 0, "expected": true },
      "phase": "off",
      "lease": null,
      "releasing_to": null,
      "controls": [],
      "native_ports": { "inputs": [], "outputs": [] },
      "error": null
    }
  ]
}
"""#

@Test func rustSnapshotDecodesNativeLeaseAndExplicitOff() throws {
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(sampleSnapshotJSON.utf8))
    #expect(snapshot.protocolVersion == 1)
    #expect(snapshot.gears.count == 2)
    #expect(snapshot.gears[0].gearID == "nanokontrol")
    #expect(snapshot.gears[0].phase == "active")
    #expect(snapshot.gears[0].nativeInputs == ["Lnx/ladyland/boot:1 | nanoKONTROL2 SLIDER/KNOB"])
    #expect(snapshot.gears[1].gearID == "maru")
    #expect(snapshot.gears[1].phase == "off")
}

@Test func nativeAccessRevokesOneGearAndNeverAllowsPhysicalOrPeerPorts() throws {
    var snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(sampleSnapshotJSON.utf8))
    snapshot.gears[1].phase = "active"
    snapshot.gears[1].lease = Lease(sessionID: "a", token: "boot:2")
    snapshot.gears[1].nativePorts = NativePorts(inputs: ["maru owned input"], outputs: ["maru owned output"])
    let access = NativeAccess()
    access.update(snapshot)
    let nano = snapshot.gears[0].nativeInputs[0]
    #expect(access.allowsInput(nano))
    #expect(access.allowsOutput("maru owned output"))
    #expect(!access.allowsInput("nanoKONTROL2 SLIDER/KNOB"))
    access.revoke(profileID: "nanokontrol")
    #expect(!access.allowsInput(nano))
    #expect(access.allowsInput("maru owned input"))
    snapshot.gears[1].lease?.sessionID = "peer"
    snapshot.sequence += 1
    access.update(snapshot)
    #expect(!access.allowsOutput("maru owned output"))
    access.clear()
    #expect(!access.allowsInput(nano))
}

@Test func delayedSnapshotCannotReenableARevokedLease() throws {
    let active = try JSONDecoder().decode(Snapshot.self, from: Data(sampleSnapshotJSON.utf8))
    let access = NativeAccess()
    access.update(active)
    var released = active
    released.sequence += 1
    released.gears[0].phase = "releasing"
    access.update(released)
    access.update(active)
    #expect(!access.allowsInput(active.gears[0].nativeInputs[0]))
}

@Test func applyGearSetupRoundTrips() throws {
    struct Envelope: Codable, Equatable {
        var gearID: String
        var leaseToken: String
        var setup: Int
        var content: SetupContent
        enum CodingKeys: String, CodingKey {
            case gearID = "gear_id", leaseToken = "lease_token", setup, content
        }
    }
    let req = Envelope(
        gearID: "roto",
        leaseToken: "boot:4",
        setup: 6,
        content: SetupContent(
            name: "VP",
            knobs: [
                KnobConfig(
                    control: 0, mode: .cc7, channel: 3, param: 20, max: 127,
                    name: "Lane 1", color: 12, haptics: .smooth(indents: [64])
                ),
                KnobConfig(
                    control: 1, mode: .cc14, channel: 3, param: 21, max: 16383,
                    name: "Mode", color: 5, haptics: .steps(names: ["PIN", "LANE", "FLOW"])
                ),
                KnobConfig(
                    control: 2, mode: .nrpn14, channel: 3, nrpnAddress: 0x0102, max: 16383,
                    name: "Pan", color: 30, haptics: .centreIndent
                ),
            ],
            switches: [
                SwitchConfig(
                    control: 7, mode: .cc7, channel: 3, param: 27, max: 127,
                    name: "TALK", color: 2, ledOn: 2, ledOff: 70, action: .push
                )
            ]
        )
    )
    let encoded = try JSONEncoder().encode(req)
    let decoded = try JSONDecoder().decode(Envelope.self, from: encoded)
    #expect(decoded == req)
}
