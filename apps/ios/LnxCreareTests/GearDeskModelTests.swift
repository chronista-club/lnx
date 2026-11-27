import Foundation
import Testing
@testable import LnxCreare

@Suite("GearCatalog & DeskKdlParser")
struct GearDeskModelTests {
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent() // LnxCreareTests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // apps
        .deletingLastPathComponent() // lnx (repoRoot)

    @Test("GearCatalog は maru を含む全 11 種の Gear のメーカー・モデル・実寸を持ち、実ファイルの gear.json / .blend と一致する")
    func catalogHasAllElevenGearsAndMatchesGearJSON() throws {
        #expect(GearCatalog.entries.count == 11)
        for entry in GearCatalog.entries {
            #expect(!entry.maker.isEmpty)
            #expect(!entry.model.isEmpty)
            #expect(entry.widthMM > 0 && entry.depthMM > 0 && entry.heightMM > 0)
            #expect(!entry.model.contains(entry.maker))

            let jsonURL = Self.repoRoot.appending(path: "gear/\(entry.id)/gear.json")
            let blendURL = Self.repoRoot.appending(path: "gear/\(entry.id)/\(entry.id).blend")
            if entry.hasModel3D {
                #expect(FileManager.default.fileExists(atPath: jsonURL.path), "missing \(jsonURL.path)")
                #expect(FileManager.default.fileExists(atPath: blendURL.path), "missing \(blendURL.path)")
                let data = try Data(contentsOf: jsonURL)
                let json = try #require(
                    try JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                #expect(json["maker"] as? String == entry.maker)
                #expect(json["model"] as? String == entry.model)
                let size = try #require((json["size"] as? [NSNumber])?.map(\.doubleValue))
                #expect(size == [entry.widthMM, entry.depthMM, entry.heightMM])
            } else {
                #expect(entry.id == "maru")
                #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
            }
        }
    }

    @Test("home と studio の机配置 KDL を解釈し、surface・gear・anchor を復元する")
    func parsesHomeAndStudioDesks() throws {
        let home = try DeskKdlParser.parse(DeskPresets.homeKDL)
        #expect(home.name == "home")
        #expect(home.footprint == DeskFootprint(centerX: -200, centerZ: -175, width: 2050, depth: 1790))
        #expect(home.surfaces.count == 3)
        #expect(home.gears.count == 10)
        #expect(home.gears.contains { $0.id == "maru" && $0.surface == "low-shelf" && $0.posX == 420 })
        #expect(home.gears.contains { $0.id == "numa" && $0.yaw == 90 })
        #expect(home.anchors.count == 2)

        let studio = try DeskKdlParser.parse(DeskPresets.studioKDL)
        #expect(studio.name == "studio")
        #expect(studio.surfaces.count == 2)
        #expect(studio.gears.count == 5)
        #expect(studio.gears.contains { $0.id == "l6max" && $0.surface == "shelf" })
        #expect(studio.anchors.map(\.id) == ["mixer"])
    }

    @Test("リポジトリの config/examples/desk-home.kdl と desk-studio.kdl が実在しプリセットと完全一致する")
    func repoExampleDeskFilesMatchPresets() throws {
        let homeURL = Self.repoRoot.appending(path: "config/examples/desk-home.kdl")
        let studioURL = Self.repoRoot.appending(path: "config/examples/desk-studio.kdl")
        #expect(FileManager.default.fileExists(atPath: homeURL.path))
        #expect(FileManager.default.fileExists(atPath: studioURL.path))
        let parsedHome = try DeskKdlParser.parse(String(contentsOf: homeURL, encoding: .utf8))
        #expect(parsedHome == DeskPresets.home)
        let parsedStudio = try DeskKdlParser.parse(String(contentsOf: studioURL, encoding: .utf8))
        #expect(parsedStudio == DeskPresets.studio)
    }

    @Test("DeskKdlParser の異常系（ヘッダ欠落・未知ノード・非正のサイズ・NaN/Inf・不正 yaw・未閉クォート）と省略時デフォルト")
    func parserRejectsInvalidInputsAndHandlesDefaults() throws {
        #expect(throws: DeskKdlError.missingDeskHeader) {
            try DeskKdlParser.parse("// comment only\n")
        }
        #expect(throws: DeskKdlError.missingDeskHeader) {
            try DeskKdlParser.parse("desk\n")
        }
        #expect(throws: DeskKdlError.self) {
            try DeskKdlParser.parse("desk \"x\" {\n  chair \"a\"\n}")
        }
        #expect(throws: DeskKdlError.self) {
            try DeskKdlParser.parse("desk \"x\" {\n  footprint center=0 0 size=0 100\n}")
        }
        #expect(throws: DeskKdlError.self) {
            try DeskKdlParser.parse("desk \"x\" {\n  footprint center=0 0 size=nan 100\n}")
        }
        #expect(throws: DeskKdlError.self) {
            try DeskKdlParser.parse("desk \"x\" {\n  gear \"roto\" surface=\"front\" pos=0 0 yaw=abc\n}")
        }
        #expect(throws: DeskKdlError.self) {
            try DeskKdlParser.parse("desk \"unclosed {\n}")
        }

        // クォート内の // はコメントとして切り落とされず、yaw 省略時は 0、footprint 省略時は 1800×1200
        let custom = try DeskKdlParser.parse("""
            desk "room // A" {
                gear "maru" surface="front" pos=10 -20}
            """)
        #expect(custom.name == "room // A")
        #expect(custom.footprint == DeskFootprint(centerX: 0, centerZ: 0, width: 1800, depth: 1200))
        #expect(custom.gears == [DeskGearPlacement(id: "maru", surface: "front", posX: 10, posZ: -20, yaw: 0)])
    }
}
