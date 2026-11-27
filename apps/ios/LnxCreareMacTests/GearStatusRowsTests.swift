import Testing
@testable import LnxCreare

private func makeGearFacts(
    _ id: String,
    present: Bool = true,
    assigned: String? = "ladyland",
    held: Bool = true,
    phase: String = "active",
    releasingTo: String? = nil,
    error: String? = nil,
    stuck: Bool = false,
    asset: Bool = true,
    me: Bool = false,
    configuring: Bool = false,
    currentSetup: Int? = nil,
    configError: String? = nil
) -> GearFacts {
    GearFacts(
        id: id,
        name: id.uppercased(),
        present: present,
        assignedTo: assigned,
        revision: 3,
        held: held,
        heldByMe: me,
        phase: phase,
        releasingTo: releasingTo,
        error: error,
        releasingStuck: stuck,
        hasGearAsset: asset,
        configuring: configuring,
        currentSetup: currentSetup,
        configError: configError
    )
}

@Suite("GearStatusRows")
struct GearStatusRowsTests {
    @Test("presence・担当・握っている・phase は独立した列として保たれる")
    func presenceAssignmentAndHolderAreSeparateColumns() {
        let rows = gearStatusRows([makeGearFacts("keystage")])
        #expect(rows[0].presence == "挿さっている")
        #expect(rows[0].assignment == "ladyland")
        #expect(rows[0].holder == "ladyland")
        #expect(rows[0].phase == "active")
        #expect(rows[0].note == nil && rows[0].tone == .normal)
    }

    @Test("担当があるのに握られていない（waiting）ときはアプリ未接続を案内する")
    func assignedButNotHeldSaysTheAppIsNotConnected() {
        let rows = gearStatusRows([makeGearFacts("xtouch", held: false, phase: "waiting")])
        #expect(rows[0].holder == "—")
        #expect(rows[0].note == "ladyland が接続していません")
    }

    @Test("見当たらない Gear は quiet になり末尾へ並ぶ")
    func missingGearIsQuietAndSortedLast() {
        let rows = gearStatusRows([
            makeGearFacts("fgdp", present: false, held: false, phase: "waiting"),
            makeGearFacts("roto"),
        ])
        #expect(rows.last?.id == "fgdp")
        #expect(rows.last?.presence == "見当たらない")
        #expect(rows.last?.tone == .quiet)
    }

    @Test("引き継ぎ停滞やエラー・設定エラーは attention になり先頭へ並び、未接続でも attention を維持する")
    func stuckHandoffAndErrorsAndConfigErrorAreAttentionAndSortedFirst() {
        let rows = gearStatusRows([
            makeGearFacts("roto", configuring: true, currentSetup: 8),
            makeGearFacts("lpd8", phase: "releasing", releasingTo: "vp", stuck: true),
            makeGearFacts("numa", present: false, phase: "error", error: "two units"),
            makeGearFacts("xtouch", configError: "serial busy"),
        ])
        #expect(rows[0].tone == .attention && rows[1].tone == .attention && rows[2].tone == .attention)
        // attention の中では「挿さっている」行が「見当たらない」行より先に来る
        #expect(rows[0].presence == "挿さっている" && rows[1].presence == "挿さっている")
        #expect(rows[2].id == "numa" && rows[2].presence == "見当たらない" && rows[2].tone == .attention)
        #expect(rows[3].id == "roto" && rows[3].tone == .normal)
        let lpd8 = rows.first { $0.id == "lpd8" }!
        #expect(lpd8.phase == "releasing → vp")
        #expect(lpd8.note?.contains("引き継ぎが止まっています") == true)
        let xtouch = rows.first { $0.id == "xtouch" }!
        #expect(xtouch.note == "設定エラー: serial busy")
        let roto = rows.first { $0.id == "roto" }!
        #expect(roto.note == "設定中… / SETUP 09")
    }

    @Test("この画面自身が lease を持つときと模型なしの表示")
    func thisWindowAndMissingGearAsset() {
        let rows = gearStatusRows([makeGearFacts("maru", assigned: "lnx", asset: false, me: true)])
        #expect(rows[0].holder == "この画面")
        #expect(rows[0].note == "模型なし")
        #expect(rows[0].tone == .normal)
    }

    @Test("同名の Gear が複数あるときは ID を添えて区別し、maker と model を分ける")
    func duplicateNamesAndMakerModel() {
        let rows = gearStatusRows([
            GearFacts(
                id: "zenith2", name: "Zenith 2", present: true, assignedTo: nil, revision: 0,
                held: false, phase: "off"
            ),
            GearFacts(
                id: "generic:zenith 2", name: "Zenith 2", present: false, assignedTo: nil,
                revision: 4, held: false, phase: "off"
            ),
            GearFacts(
                id: "keystage", name: "Keystage", present: true, assignedTo: nil, revision: 0,
                held: false, phase: "off", maker: "KORG", model: "Keystage 61"
            ),
        ])
        #expect(rows.map(\.name).contains("Zenith 2（zenith2）"))
        #expect(rows.map(\.name).contains("Zenith 2（generic:zenith 2）"))
        #expect(rows.map(\.name).contains("KORG Keystage 61"))
        let ks = rows.first { $0.id == "keystage" }!
        #expect(ks.maker == "KORG" && ks.model == "Keystage 61")
        #expect(makerAndModel(fromGearJSON: ["maker": "AKAI", "model": "LPD8 mk2"]).maker == "AKAI")
    }

    @Test("phaseTone と bundleMatchesClient")
    func phaseToneAndBundleMatching() {
        #expect(gearPhaseTone("active") == .active)
        #expect(gearPhaseTone("waiting") == .waiting)
        #expect(gearPhaseTone("releasing → vp") == .releasing)
        #expect(gearPhaseTone("error") == .error)
        #expect(gearPhaseTone("off") == .off)
        #expect(bundleMatchesClient(bundleID: "tech.anycreative.vp", clientID: "vp"))
        #expect(bundleMatchesClient(bundleID: "club.chronista.ladyland", clientID: "ladyland"))
        #expect(!bundleMatchesClient(bundleID: "club.chronista.lnx.creare", clientID: "vp"))
    }
}
