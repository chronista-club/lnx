import Foundation
import Testing
@testable import LnxCreare

@Suite("GearLogLines")
struct GearLogLinesTests {
    @Test("流れのログ行から時刻・レベル・target・本文を切り出す")
    func flowLineSplitsTimeLevelTargetAndMessage() throws {
        let l = try #require(
            parseGearLogLine(
                "2026-11-27T06:32:11.558367Z  INFO lnx_server::gear::runtime: keystage: plugged in",
                id: 1
            )
        )
        #expect(l.level == .info)
        #expect(l.target == "lnx_server::gear::runtime")
        #expect(l.message == "keystage: plugged in")
        #expect(l.fields.isEmpty)
        #expect(!isGearTraceLine(l))
    }

    @Test("MIDI トレース行は空白を含むポート名を保ったまま GearTraceRow に変換される")
    func traceLineKeepsSpacesInsideValuesAndBecomesARow() throws {
        let raw = #"2026-11-27T14:36:49.093712Z  INFO FWD | B7 4F 1F dir="dev→app" device=lpd8 app=vp port=LPD8 mk2 kind="cc""#
        let l = try #require(parseGearLogLine(raw, id: 3))
        #expect(isGearTraceLine(l))
        #expect(l.fields["port"] == "LPD8 mk2")
        #expect(l.fields["kind"] == "cc")
        let row = try #require(gearTraceRow(l))
        #expect(row.direction == "dev→app" && row.gear == "lpd8" && row.app == "vp")
        #expect(row.verdict == "FWD" && row.kind == "cc" && row.detail == "B7 4F 1F")
    }

    @Test("仮想ポート開閉行と区切り行・マルチバイト文字境界の分割")
    func bridgeOpenAndMarkerAndMultibyteChunks() throws {
        let raw = #"2026-11-27T06:32:12.1Z  INFO OPEN bridge | in ["Lnx/vp/x:1/1 | LPD8 mk2"] | out ["Lnx/vp/x:1/2 | LPD8 mk2"] device=lpd8 app=vp token=x:1"#
        let line = try #require(parseGearLogLine(raw, id: 4))
        let row = try #require(gearTraceRow(line))
        #expect(row.verdict == "OPEN bridge")
        #expect(row.detail.hasPrefix("in [") && row.detail.contains("out ["))
        #expect(row.gear == "lpd8")

        let marker = try #require(
            parseGearLogLine("2026-11-27T06:00:00.0Z  INFO ---- MIDI trace on ----", id: 5)
        )
        #expect(isGearTraceLine(marker))
        #expect(gearTraceRow(marker) == nil)

        let mbLine = #"2026-11-27T01:02:03.4Z  INFO FWD | B7 dir="dev→app" device=maru"#
        let bytes = Array((mbLine + "\n").utf8)
        for cut in 1..<bytes.count {
            var splitter = GearLineSplitter()
            let first = splitter.push(Data(bytes[..<cut]))
            let second = splitter.push(Data(bytes[cut...]))
            #expect(first + second == [mbLine], "cut at \(cut)")
        }
    }

    @Test("通信ライブラリ行・クロック行のフィルタとクエリ検索")
    func libraryNoiseClockAndQueryFiltering() throws {
        let noise = try #require(
            parseGearLogLine(
                "2026-11-27T06:00:00.0Z  INFO unison::network::quic: New QUIC connection from: [::1]:1",
                id: 8
            )
        )
        #expect(isGearLibraryNoise(noise))
        let clock = try #require(
            parseGearLogLine(
                #"2026-11-27T06:24:41.8Z  INFO FWD | F8 dir="dev→app" device=keystage app=ladyland port=Keystage KBD/CTRL kind="clock""#,
                id: 10
            )
        )
        let clockRow = try #require(gearTraceRow(clock))
        #expect(isGearClockRow(clockRow))
        #expect(gearLogMatches(clock, query: "keystage"))
        #expect(!gearLogMatches(clock, query: "maru"))
    }
}
