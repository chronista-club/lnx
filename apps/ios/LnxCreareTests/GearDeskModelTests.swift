import Foundation
import Testing
@testable import LnxCreare

@Suite("GearCatalog & DeskKdlParser")
struct GearDeskModelTests {
    @Test("GearCatalog は maru を含む全 11 種の Gear のメーカー・モデル・実寸を持つ")
    func catalogHasAllElevenGears() {
        #expect(GearCatalog.entries.count == 11)
        for entry in GearCatalog.entries {
            #expect(!entry.maker.isEmpty)
            #expect(!entry.model.isEmpty)
            #expect(entry.widthMM > 0 && entry.depthMM > 0 && entry.heightMM > 0)
            #expect(!entry.model.contains(entry.maker))
        }
        let maru = try! #require(GearCatalog.entry(for: "maru"))
        #expect(maru.maker == "Chronista" && maru.model == "maru" && !maru.hasModel3D)
        let roto = try! #require(GearCatalog.entry(for: "roto"))
        #expect(roto.maker == "Melbourne Instruments" && roto.hasModel3D)
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

    @Test("リポジトリの config/examples/desk-home.kdl と desk-studio.kdl が存在すれば同じ構造で読める")
    func repoExampleDeskFilesMatchPresets() throws {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeURL = repoRoot.appending(path: "config/examples/desk-home.kdl")
        let studioURL = repoRoot.appending(path: "config/examples/desk-studio.kdl")
        if FileManager.default.fileExists(atPath: homeURL.path) {
            let parsedHome = try DeskKdlParser.parse(String(contentsOf: homeURL, encoding: .utf8))
            #expect(parsedHome == DeskPresets.home)
        }
        if FileManager.default.fileExists(atPath: studioURL.path) {
            let parsedStudio = try DeskKdlParser.parse(String(contentsOf: studioURL, encoding: .utf8))
            #expect(parsedStudio == DeskPresets.studio)
        }
    }
}
