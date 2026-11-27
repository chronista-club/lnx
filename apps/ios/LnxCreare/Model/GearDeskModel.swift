import Foundation

// Gear カタログ（gear/<id>/gear.json の意味の層）と机配置（desk.kdl）の純粋データ・計算層（[data + calculations]）。
// Mac と iPad / iPhone の両方で共有する。

struct GearCatalogEntry: Sendable, Equatable, Identifiable {
    var id: String
    var maker: String
    var model: String
    /// 幅 W (mm)
    var widthMM: Double
    /// 奥行き D (mm)
    var depthMM: Double
    /// 高さ H (mm)
    var heightMM: Double
    /// 3D 資産（gear/<id>/<id>.blend）が存在するか
    var hasModel3D: Bool

    var displayName: String { "\(maker) \(model)" }
}

enum GearCatalog {
    static let entries: [GearCatalogEntry] = [
        GearCatalogEntry(
            id: "roto", maker: "Melbourne Instruments", model: "ROTO-CONTROL",
            widthMM: 341, depthMM: 99, heightMM: 44, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "lpd8", maker: "AKAI", model: "LPD8 mk2",
            widthMM: 306, depthMM: 81, heightMM: 34, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "nanokontrol", maker: "KORG", model: "nanoKONTROL2",
            widthMM: 325, depthMM: 83, heightMM: 30, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "keystage", maker: "KORG", model: "Keystage 61",
            widthMM: 979, depthMM: 234, heightMM: 82, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "numa", maker: "Studiologic", model: "Numa Compact X SE",
            widthMM: 1270, depthMM: 224, heightMM: 100, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "minilab", maker: "Arturia", model: "MiniLab mkII",
            widthMM: 355, depthMM: 220, heightMM: 50, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "fgdp", maker: "Yamaha", model: "FGDP-50",
            widthMM: 223, depthMM: 223, heightMM: 51, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "xtouch", maker: "Behringer", model: "X-TOUCH",
            widthMM: 452, depthMM: 301, heightMM: 100, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "l6max", maker: "ZOOM", model: "LiveTrak L6max",
            widthMM: 284, depthMM: 114, heightMM: 46.5, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "zenith2", maker: "Antelope Audio", model: "Zenith 2",
            widthMM: 135, depthMM: 130, heightMM: 60, hasModel3D: true
        ),
        GearCatalogEntry(
            id: "maru", maker: "Chronista", model: "maru",
            widthMM: 90, depthMM: 90, heightMM: 45, hasModel3D: false
        ),
    ]

    static func entry(for id: String) -> GearCatalogEntry? {
        entries.first { $0.id == id }
    }
}

struct DeskFootprint: Sendable, Equatable {
    var centerX: Double
    var centerZ: Double
    var width: Double
    var depth: Double
}

struct DeskSurface: Sendable, Equatable, Identifiable {
    var id: String
    var centerX: Double
    var centerZ: Double
    var width: Double
    var depth: Double
    var elevation: Double
    var thickness: Double
}

struct DeskGearPlacement: Sendable, Equatable, Identifiable {
    var id: String
    var surface: String
    var posX: Double
    var posZ: Double
    var yaw: Double
}

struct DeskAnchor: Sendable, Equatable, Identifiable {
    var id: String
    var surface: String
    var posX: Double
    var posZ: Double
}

struct DeskLayout: Sendable, Equatable, Identifiable {
    var name: String
    var footprint: DeskFootprint
    var surfaces: [DeskSurface]
    var gears: [DeskGearPlacement]
    var anchors: [DeskAnchor]

    var id: String { name }
}

enum DeskKdlError: LocalizedError, Equatable {
    case missingDeskHeader
    case invalidNode(String)

    var errorDescription: String? {
        switch self {
        case .missingDeskHeader: "desk ノードが見つかりません"
        case .invalidNode(let line): "机配置の行を解釈できません: \(line)"
        }
    }
}

/// config/examples/desk-*.kdl の机スキーマを解釈する純粋パーサ
enum DeskKdlParser {
    private static func parseFiniteDouble(_ s: String) -> Double? {
        guard let v = Double(s), v.isFinite, abs(v) <= 1_000_000 else { return nil }
        return v
    }

    static func parse(_ source: String) throws -> DeskLayout {
        var deskName: String?
        var footprint = DeskFootprint(centerX: 0, centerZ: 0, width: 1800, depth: 1200)
        var surfaces: [DeskSurface] = []
        var gears: [DeskGearPlacement] = []
        var anchors: [DeskAnchor] = []

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripLineComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line == "}" { continue }
            let tokens = try tokenize(line)
            guard let head = tokens.first else { continue }
            switch head {
            case "desk":
                guard tokens.count >= 2 else { throw DeskKdlError.missingDeskHeader }
                let name = unquote(tokens[1])
                guard !name.isEmpty else { throw DeskKdlError.missingDeskHeader }
                deskName = name
            case "footprint":
                let props = parseProps(Array(tokens.dropFirst()))
                guard let center = props["center"], center.count == 2,
                      let cx = parseFiniteDouble(center[0]), let cz = parseFiniteDouble(center[1]),
                      let size = props["size"], size.count == 2,
                      let w = parseFiniteDouble(size[0]), let d = parseFiniteDouble(size[1]),
                      w > 0, d > 0
                else { throw DeskKdlError.invalidNode(line) }
                footprint = DeskFootprint(centerX: cx, centerZ: cz, width: w, depth: d)
            case "surface":
                guard tokens.count >= 2 else { throw DeskKdlError.invalidNode(line) }
                let sid = unquote(tokens[1])
                let props = parseProps(Array(tokens.dropFirst(2)))
                guard !sid.isEmpty,
                      let center = props["center"], center.count == 2,
                      let cx = parseFiniteDouble(center[0]), let cz = parseFiniteDouble(center[1]),
                      let size = props["size"], size.count == 2,
                      let w = parseFiniteDouble(size[0]), let d = parseFiniteDouble(size[1]),
                      w > 0, d > 0,
                      let elevStr = props["elevation"]?.first, props["elevation"]?.count == 1,
                      let elev = parseFiniteDouble(elevStr),
                      let thickStr = props["thickness"]?.first, props["thickness"]?.count == 1,
                      let thick = parseFiniteDouble(thickStr), thick >= 0
                else { throw DeskKdlError.invalidNode(line) }
                surfaces.append(
                    DeskSurface(
                        id: sid, centerX: cx, centerZ: cz, width: w, depth: d,
                        elevation: elev, thickness: thick
                    )
                )
            case "gear":
                guard tokens.count >= 2 else { throw DeskKdlError.invalidNode(line) }
                let gid = unquote(tokens[1])
                let props = parseProps(Array(tokens.dropFirst(2)))
                guard !gid.isEmpty,
                      let surf = props["surface"]?.first.map(unquote), props["surface"]?.count == 1,
                      !surf.isEmpty,
                      let pos = props["pos"], pos.count == 2,
                      let px = parseFiniteDouble(pos[0]), let pz = parseFiniteDouble(pos[1])
                else { throw DeskKdlError.invalidNode(line) }
                let yaw: Double
                if let yawVals = props["yaw"] {
                    guard yawVals.count == 1, let parsedYaw = parseFiniteDouble(yawVals[0]) else {
                        throw DeskKdlError.invalidNode(line)
                    }
                    yaw = parsedYaw
                } else {
                    yaw = 0
                }
                gears.append(DeskGearPlacement(id: gid, surface: surf, posX: px, posZ: pz, yaw: yaw))
            case "anchor":
                guard tokens.count >= 2 else { throw DeskKdlError.invalidNode(line) }
                let aid = unquote(tokens[1])
                let props = parseProps(Array(tokens.dropFirst(2)))
                guard !aid.isEmpty,
                      let surf = props["surface"]?.first.map(unquote), props["surface"]?.count == 1,
                      !surf.isEmpty,
                      let pos = props["pos"], pos.count == 2,
                      let px = parseFiniteDouble(pos[0]), let pz = parseFiniteDouble(pos[1])
                else { throw DeskKdlError.invalidNode(line) }
                anchors.append(DeskAnchor(id: aid, surface: surf, posX: px, posZ: pz))
            default:
                throw DeskKdlError.invalidNode(line)
            }
        }

        guard let deskName else { throw DeskKdlError.missingDeskHeader }
        return DeskLayout(
            name: deskName,
            footprint: footprint,
            surfaces: surfaces,
            gears: gears,
            anchors: anchors
        )
    }

    private static func stripLineComment(_ line: String) -> String {
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if chars[i] == "\"" { inQuotes.toggle() }
            if !inQuotes, i + 1 < chars.count, chars[i] == "/", chars[i + 1] == "/" {
                return String(chars[..<i])
            }
            i += 1
        }
        return line
    }

    private static func tokenize(_ line: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if !inQuotes && (ch == " " || ch == "\t" || ch == "{" || ch == "}") {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if inQuotes {
            throw DeskKdlError.invalidNode(line)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func unquote(_ s: String) -> String {
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    /// `center=-200 -175 size=2050 1790` のような空白区切りの複数値プロパティも束ねる
    private static func parseProps(_ tokens: [String]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        var currentKey: String?
        for tok in tokens {
            if let eq = tok.firstIndex(of: "=") {
                let key = String(tok[..<eq])
                let val = String(tok[tok.index(after: eq)...])
                currentKey = key
                out[key, default: []].append(val)
            } else if let key = currentKey {
                out[key, default: []].append(tok)
            }
        }
        return out
    }
}

enum DeskPresets {
    static let homeKDL = """
        desk "home" {
            footprint center=-200 -175 size=2050 1790

            surface "front" center=0 -566.5 size=1650 917 elevation=740 thickness=40
            surface "left-numa" center=-1069 20 size=312 1400 elevation=740 thickness=40
            surface "low-shelf" center=0 -739.25 size=1560 661.5 elevation=850 thickness=40

            gear "keystage" surface="front" pos=0 -225 yaw=0
            gear "numa" surface="left-numa" pos=-1025 20 yaw=90
            gear "xtouch" surface="low-shelf" pos=0 -900 yaw=0
            gear "roto" surface="low-shelf" pos=-430 -960 yaw=0
            gear "fgdp" surface="low-shelf" pos=-550 -520 yaw=0
            gear "lpd8" surface="low-shelf" pos=-180 -520 yaw=0
            gear "nanokontrol" surface="low-shelf" pos=180 -520 yaw=0
            gear "minilab" surface="low-shelf" pos=550 -520 yaw=0
            gear "zenith2" surface="front" pos=640 -330 yaw=-15
            gear "maru" surface="low-shelf" pos=420 -520 yaw=0

            anchor "mixer" surface="low-shelf" pos=-120 -680
            anchor "track-knobs" surface="low-shelf" pos=120 -680
        }
        """

    static let studioKDL = """
        desk "studio" {
            footprint center=0 -200 size=1800 1200

            surface "front" center=0 -500 size=1600 800 elevation=740 thickness=40
            surface "shelf" center=0 -850 size=1400 300 elevation=850 thickness=30

            gear "keystage" surface="front" pos=0 -300 yaw=0
            gear "l6max" surface="shelf" pos=0 -850 yaw=0
            gear "nanokontrol" surface="shelf" pos=-450 -850 yaw=0
            gear "lpd8" surface="shelf" pos=450 -850 yaw=0
            gear "roto" surface="front" pos=600 -250 yaw=0

            anchor "mixer" surface="shelf" pos=0 -850
        }
        """

    static let home: DeskLayout = try! DeskKdlParser.parse(homeKDL)
    static let studio: DeskLayout = try! DeskKdlParser.parse(studioKDL)
    static let all: [DeskLayout] = [home, studio]
}
