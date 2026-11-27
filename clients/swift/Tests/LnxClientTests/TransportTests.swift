import Foundation
import Testing
@testable import LnxClient

@Test(.enabled(if: ProcessInfo.processInfo.environment["LNX_TEST_SERVER"] != nil))
func swiftSDKConnectsToRustAndAcknowledgesOnlyAfterAppCleanup() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lnx-sdk-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LNX_TEST_SERVER"]!)
    process.arguments = [directory.path]
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
    let endpoint = directory.appendingPathComponent("endpoint.json")
    for _ in 0..<100 {
        if FileManager.default.fileExists(atPath: endpoint.path) { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(FileManager.default.fileExists(atPath: endpoint.path))
    let (a, first) = try await Client.connect(
        endpointURL: endpoint, clientID: "swift-a", displayName: "Swift A", nativeMIDI: false
    )
    #expect(first.protocolVersion == 1)
    let (b, _) = try await Client.connect(
        endpointURL: endpoint, clientID: "swift-b", displayName: "Swift B", nativeMIDI: false
    )
    let enabled = try await a.setEnabled(gearID: "nano", enabled: true, expectedRevision: 0)
    let token = try #require(enabled.gears.first { $0.gearID == "nano" }?.lease?.token)
    do {
        _ = try await a.sendMIDI(gearID: "nano", leaseToken: "old", portName: "output", bytes: [0x90, 60, 100])
        Issue.record("stale output was accepted")
    } catch let error as ProtocolFailure {
        #expect(error.code == "stale_lease")
    }
    do {
        _ = try await b.setEnabled(gearID: "nano", enabled: true, expectedRevision: 1)
        Issue.record("takeover without confirmation was accepted")
    } catch let error as ProtocolFailure {
        #expect(error.code == "conflict")
    }
    _ = try await b.setEnabled(gearID: "nano", enabled: true, expectedRevision: 1, takeover: true)
    for await event in a.events {
        if case let .quiesce(gearID, _, leaseToken) = event {
            #expect(gearID == "nano")
            #expect(leaseToken == token)
            break
        }
    }
    let pending = try await b.snapshot()
    #expect(pending.gears.first { $0.gearID == "nano" }?.phase == "releasing")
    _ = try await a.quiesced(gearID: "nano", leaseToken: token)
    var successor = try await b.snapshot()
    for _ in 0..<50 {
        if successor.gears.first(where: { $0.gearID == "nano" })?.phase == "active" { break }
        try await Task.sleep(for: .milliseconds(20))
        successor = try await b.snapshot()
    }
    let nanoAfter = try #require(successor.gears.first { $0.gearID == "nano" })
    #expect(successor.owns(nanoAfter))

    // ROTO setup RPC 往復検証（setGearSetups → setEnabled → selectSetup → applyGearSetup）
    _ = try await a.setGearSetups(gearID: "roto", setups: [6, 7])
    let rotoEnabled = try await a.setEnabled(gearID: "roto", enabled: true, expectedRevision: 0)
    let rotoLease = try #require(rotoEnabled.gears.first { $0.gearID == "roto" }?.lease?.token)
    _ = try await a.selectSetup(gearID: "roto", leaseToken: rotoLease, setup: 7)
    _ = try await a.applyGearSetup(
        gearID: "roto",
        leaseToken: rotoLease,
        setup: 7,
        content: SetupContent(name: "SwiftTest")
    )
    var rotoSettled = try await a.snapshot()
    for _ in 0..<50 {
        if rotoSettled.gears.first(where: { $0.gearID == "roto" })?.configuring == false { break }
        try await Task.sleep(for: .milliseconds(20))
        rotoSettled = try await a.snapshot()
    }
    let rotoFinal = try #require(rotoSettled.gears.first { $0.gearID == "roto" })
    #expect(rotoFinal.configuring == false)
    #expect(rotoFinal.currentSetup == 7)

    await a.close()
    await b.close()
}
