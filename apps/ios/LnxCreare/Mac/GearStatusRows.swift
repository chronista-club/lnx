#if os(macOS)
import Foundation

// Gear ステータス一覧の純粋計算層（[calculations]）。
// 「挿さっている（presence）」と「担当（assignment）」と「握っている（holder）」と「phase」は別の事実なので別の列に出し、潰さない。

/// Snapshot の GearView から一覧表示に要る事実だけを写した値型
struct GearFacts: Sendable, Equatable {
    var id: String
    var name: String
    var present: Bool
    var assignedTo: String?
    var revision: UInt64
    var held: Bool
    var heldByMe: Bool
    var phase: String
    var releasingTo: String?
    var error: String?
    var releasingStuck: Bool
    var hasGearAsset: Bool
    var maker: String?
    var model: String?
    var configuring: Bool
    var currentSetup: Int?
    var configError: String?

    init(
        id: String,
        name: String,
        present: Bool,
        assignedTo: String?,
        revision: UInt64,
        held: Bool,
        heldByMe: Bool = false,
        phase: String,
        releasingTo: String? = nil,
        error: String? = nil,
        releasingStuck: Bool = false,
        hasGearAsset: Bool = true,
        maker: String? = nil,
        model: String? = nil,
        configuring: Bool = false,
        currentSetup: Int? = nil,
        configError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.present = present
        self.assignedTo = assignedTo
        self.revision = revision
        self.held = held
        self.heldByMe = heldByMe
        self.phase = phase
        self.releasingTo = releasingTo
        self.error = error
        self.releasingStuck = releasingStuck
        self.hasGearAsset = hasGearAsset
        self.maker = maker
        self.model = model
        self.configuring = configuring
        self.currentSetup = currentSetup
        self.configError = configError
    }

    /// 一覧に出す名前: 「KORG Keystage 61」のように「どこの何か」。gear.json が無ければ snapshot の名前
    var displayName: String {
        if let maker, let model { return "\(maker) \(model)" }
        return model ?? name
    }
}

enum GearRowTone: Sendable, Equatable {
    case normal
    case quiet
    case attention

    var rank: Int {
        switch self {
        case .attention: 0
        case .normal: 1
        case .quiet: 2
        }
    }
}

/// Gear ステータス一覧の 1 行。文言と並べ順はここで決める（画面は並べるだけ）
struct GearRow: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var maker: String?
    var model: String
    var presence: String
    var assignment: String
    var holder: String
    var phase: String
    var note: String?
    var tone: GearRowTone
    var revision: UInt64
}

func gearStatusRows(_ gears: [GearFacts]) -> [GearRow] {
    var nameCount: [String: Int] = [:]
    for g in gears { nameCount[g.displayName, default: 0] += 1 }
    return gears.map { g in
        var notes: [String] = []
        var tone: GearRowTone = .normal
        if g.phase == "error" || g.error != nil {
            tone = .attention
            notes.append(g.error ?? "エラー")
        }
        if let configError = g.configError {
            tone = .attention
            notes.append("設定エラー: \(configError)")
        }
        if g.configuring {
            notes.append("設定中…")
        }
        if let setup = g.currentSetup {
            notes.append(String(format: "SETUP %02d", setup + 1))
        }
        if g.releasingStuck {
            tone = .attention
            notes.append("引き継ぎが止まっています（\(g.releasingTo ?? "?") へ）")
        }
        if let to = g.assignedTo, g.present, !g.held, g.phase == "waiting" {
            notes.append("\(to) が接続していません")
        }
        if !g.present {
            tone = tone == .attention ? .attention : .quiet
        }
        if !g.hasGearAsset {
            notes.append("模型なし")
        }

        let holder: String
        if g.held {
            holder = g.heldByMe ? "この画面" : (g.assignedTo ?? "？")
        } else {
            holder = "—"
        }
        let phase = g.phase == "releasing" ? "releasing → \(g.releasingTo ?? "?")" : g.phase
        let dup = (nameCount[g.displayName] ?? 0) > 1
        let shownName = dup ? "\(g.displayName)（\(g.id)）" : g.displayName
        let baseModel = g.model ?? g.name
        return GearRow(
            id: g.id,
            name: shownName,
            maker: g.maker,
            model: dup ? "\(baseModel)（\(g.id)）" : baseModel,
            presence: g.present ? "挿さっている" : "見当たらない",
            assignment: g.assignedTo ?? "なし",
            holder: holder,
            phase: phase,
            note: notes.isEmpty ? nil : notes.joined(separator: " / "),
            tone: tone,
            revision: g.revision
        )
    }
    .sorted { a, b in
        if a.tone != b.tone { return a.tone.rank < b.tone.rank }
        if (a.presence == "挿さっている") != (b.presence == "挿さっている") {
            return a.presence == "挿さっている"
        }
        return a.name < b.name
    }
}

/// gear.json から maker / model を読む純粋関数
func makerAndModel(fromGearJSON json: [String: Any]) -> (maker: String?, model: String?) {
    (json["maker"] as? String, json["model"] as? String)
}

enum GearPhaseTone: Sendable, Equatable {
    case off, waiting, active, releasing, error
}

func gearPhaseTone(_ phase: String) -> GearPhaseTone {
    switch phase {
    case "active": return .active
    case "waiting": return .waiting
    case "error": return .error
    default:
        return phase.hasPrefix("releasing") ? .releasing : .off
    }
}

/// client_id（`vp` / `ladyland`）と bundle id の末尾（`tech.anycreative.vp` / `club.chronista.ladyland`）を照合する
func bundleMatchesClient(bundleID: String, clientID: String) -> Bool {
    let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    return last.lowercased() == clientID.lowercased()
}
#endif
