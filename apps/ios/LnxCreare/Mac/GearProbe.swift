#if os(macOS)
import Foundation
import LnxClient

struct GearSummary: Sendable, Equatable {
    var present: Int
    var releasingStuck: Int
    var errors: Int
}

struct GearProbeResult: Sendable, Equatable {
    var connected: Bool
    var serviceVersion: String?
    var serviceExecutable: String?
    var summary: GearSummary
    var gears: [GearFacts]

    static let empty = GearProbeResult(
        connected: false,
        serviceVersion: nil,
        serviceExecutable: nil,
        summary: GearSummary(present: 0, releasingStuck: 0, errors: 0),
        gears: []
    )
}

protocol GearProbing: Sendable {
    func probe() async -> GearProbeResult
    func close() async
}

/// テスト用の何もしない probe
struct NoopGearProbe: GearProbing {
    func probe() async -> GearProbeResult { .empty }
    func close() async {}
}

/// lnx-server の endpoint.json を読んで gear channel に接続し、観察専用で Snapshot を引く
actor GearProbe: GearProbing {
    private var releasingSince: [String: Date] = [:]
    private var client: Client?
    private var connecting: Task<(Client, Snapshot), Error>?
    private var closed = false
    let stuckAfter: TimeInterval = 5

    func close() async {
        closed = true
        connecting?.cancel()
        await drop()
    }

    private func drop(only: Client? = nil) async {
        guard let stale = client, only == nil || only === stale else { return }
        client = nil
        await stale.close()
    }

    private func connect(_ url: URL) async throws -> (Client, Snapshot) {
        let task = connecting ?? Task {
            try await Client.connect(
                endpointURL: url,
                clientID: "club.chronista.lnx.creare.mac",
                displayName: "lnx creare",
                nativeMIDI: false
            )
        }
        connecting = task
        defer { if connecting == task { connecting = nil } }
        let (connected, first) = try await task.value
        if closed {
            if connecting == task {
                connecting = nil
                await connected.close()
            }
            throw CancellationError()
        }
        if client == nil { client = connected }
        return (connected, first)
    }

    func probe() async -> GearProbeResult {
        let url = Client.defaultEndpointURL
        guard !closed else { return .empty }
        guard FileManager.default.fileExists(atPath: url.path) else {
            await drop()
            return .empty
        }
        let using = client
        do {
            let snapshot: Snapshot
            if let client {
                snapshot = try await client.snapshot()
            } else {
                snapshot = try await connect(url).1
            }
            let summary = summarize(snapshot)
            return GearProbeResult(
                connected: true,
                serviceVersion: snapshot.service?.version,
                serviceExecutable: snapshot.service?.executable,
                summary: summary,
                gears: facts(snapshot)
            )
        } catch {
            if let using { await drop(only: using) }
            return .empty
        }
    }

    private func gearAssetDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/club.chronista.lnx-server/gear")
    }

    private func hasAsset(_ id: String) -> Bool {
        let dist = gearAssetDir().appending(path: "\(id).usdz")
        if FileManager.default.fileExists(atPath: dist.path) { return true }
        if Bundle.main.url(forResource: id, withExtension: "usdz") != nil { return true }
        // 3D 資産の配布ディレクトリ自体がまだ無い場合は「模型なし」の警告を抑制する
        return !FileManager.default.fileExists(atPath: gearAssetDir().path)
    }

    private func makerModel(_ id: String) -> (String?, String?) {
        let url = gearAssetDir().appending(path: "\(id).json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, nil) }
        return makerAndModel(fromGearJSON: json)
    }

    private func facts(_ snapshot: Snapshot) -> [GearFacts] {
        let now = Date()
        return snapshot.gears.map { g in
            let stuck = g.phase == "releasing"
                && releasingSince[g.gearID].map { now.timeIntervalSince($0) > stuckAfter } == true
            let mm = makerModel(g.profileID)
            return GearFacts(
                id: g.gearID,
                name: g.name,
                present: g.present,
                assignedTo: g.assignment.clientID,
                revision: g.assignment.revision,
                held: g.lease != nil,
                heldByMe: g.lease?.sessionID == snapshot.sessionID,
                phase: g.phase,
                releasingTo: g.releasingTo,
                error: g.error,
                releasingStuck: stuck,
                hasGearAsset: hasAsset(g.profileID),
                maker: mm.0,
                model: mm.1,
                configuring: g.configuring ?? false,
                currentSetup: g.currentSetup,
                configError: g.configError
            )
        }
    }

    private func summarize(_ snapshot: Snapshot) -> GearSummary {
        let now = Date()
        var stuck = 0
        var errors = 0
        var present = 0
        var seen: Set<String> = []
        for g in snapshot.gears {
            if g.present { present += 1 }
            if g.error != nil || g.configError != nil { errors += 1 }
            if g.phase == "releasing" {
                seen.insert(g.gearID)
                let since = releasingSince[g.gearID] ?? now
                releasingSince[g.gearID] = since
                if now.timeIntervalSince(since) > stuckAfter { stuck += 1 }
            }
        }
        releasingSince = releasingSince.filter { seen.contains($0.key) }
        return GearSummary(present: present, releasingStuck: stuck, errors: errors)
    }
}
#endif
