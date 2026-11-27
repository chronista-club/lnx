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
        #expect(gearTraceRow(l) == nil)
    }

    @Test("WARN / ERROR の障害ログはトレース行と誤判定されず流れタブに残る")
    func warnAndErrorLinesStayInFlow() throws {
        let fault = try #require(
            parseGearLogLine(
                "2026-11-27T06:32:12.0Z  WARN lnx_server::gear::runtime: roto: MIDI I/O fault: device unplugged (boot:1)",
                id: 2
            )
        )
        #expect(fault.level == .warn)
        #expect(!isGearTraceLine(fault))
        #expect(gearTraceRow(fault) == nil)

        // target 無しで device= が含まれる WARN でも WARN レベルなのでトレース行に誤分類しない
        let legacyWarn = try #require(
            parseGearLogLine(
                "2026-11-27T06:32:12.0Z  WARN MIDI I/O fault device=roto token=boot:1",
                id: 3
            )
        )
        #expect(!isGearTraceLine(legacyWarn))
    }

    @Test("trace.rs が出す全 6 種のトレース行（lnx_trace target 付き / 無し両方）が正しく解釈される")
    func allSixTraceFormatsAreParsed() throws {
        let rawLines = [
            "2026-11-27T14:36:48.000000Z  INFO lnx_trace: ---- MIDI trace on ----",
            #"2026-11-27T14:36:49.093712Z  INFO lnx_trace: FWD | B7 4F 1F dir="dev→app" device=lpd8 app=vp port=LPD8 mk2 kind="cc""#,
            #"2026-11-27T14:36:49.100000Z  INFO lnx_trace: SENT | F0 7D 01 F7 dir="svc→dev" device=roto app=vp via="SendMidi" kind="sysex""#,
            #"2026-11-27T14:36:49.200000Z  INFO lnx_trace: OVERFLOW queue full; lease stopped dir="app→svc" device=keystage app=ladyland"#,
            #"2026-11-27T14:36:49.300000Z  INFO lnx_trace: OPEN bridge | in ["Lnx/vp/x:1/1 | LPD8 mk2"] | out ["Lnx/vp/x:1/2 | LPD8 mk2"] device=lpd8 app=vp token=x:1"#,
            #"2026-11-27T14:36:49.400000Z  INFO lnx_trace: CLOSE bridge device=lpd8 token=x:1"#,
            "2026-11-27T14:36:50.000000Z  INFO lnx_trace: ---- MIDI trace off ----",
        ]
        let parsed = try rawLines.enumerated().map { idx, raw in
            try #require(parseGearLogLine(raw, id: idx + 10))
        }
        #expect(parsed.allSatisfy { $0.target == "lnx_trace" && isGearTraceLine($0) })
        let rows = parsed.compactMap(gearTraceRow)
        #expect(rows.count == 5, "on/off の区切り 2 行以外はすべて TraceRow になる")
        #expect(rows[0].direction == "dev→app" && rows[0].gear == "lpd8" && rows[0].app == "vp")
        #expect(rows[0].verdict == "FWD" && rows[0].kind == "cc" && rows[0].detail == "B7 4F 1F")
        #expect(parsed[1].fields["port"] == "LPD8 mk2")
        #expect(rows[1].direction == "svc→dev" && rows[1].gear == "roto" && rows[1].verdict == "SENT")
        #expect(parsed[2].fields["via"] == "SendMidi")
        #expect(rows[2].verdict == "OVERFLOW queue full; lease stopped" && rows[2].gear == "keystage")
        #expect(rows[3].verdict == "OPEN bridge" && rows[3].detail.contains("out ["))
        #expect(rows[4].verdict == "CLOSE bridge" && rows[4].gear == "lpd8")
    }

    @Test("マルチバイト文字境界の分割と reset()、最新ログファイル選択")
    func multibyteChunksResetAndNewestFile() throws {
        let mbLine = #"2026-11-27T01:02:03.4Z  INFO lnx_trace: FWD | B7 dir="dev→app" device=maru"#
        let bytes = Array((mbLine + "\n").utf8)
        for cut in 1..<bytes.count {
            var splitter = GearLineSplitter()
            let first = splitter.push(Data(bytes[..<cut]))
            let second = splitter.push(Data(bytes[cut...]))
            #expect(first + second == [mbLine], "cut at \(cut)")
        }

        var resettable = GearLineSplitter()
        #expect(resettable.push(Data("partial-without-newline".utf8)).isEmpty)
        resettable.reset()
        #expect(resettable.push(Data("fresh-line\n".utf8)) == ["fresh-line"])

        let names = ["lnx-server.log.2026-11-26", "lnx-server.log.2026-11-27", "other.txt"]
        #expect(newestGearLogFile(names, prefix: "lnx-server.log") == "lnx-server.log.2026-11-27")
        #expect(newestGearLogFile(["lnx-server.log"], prefix: "lnx-server.log") == "lnx-server.log")
        #expect(newestGearLogFile([], prefix: "lnx-server.log") == nil)
    }

    @Test("通信ライブラリ行・クロック行・Active Sensing 行のフィルタとクエリ検索")
    func libraryNoiseClockAndQueryFiltering() throws {
        let noise = try #require(
            parseGearLogLine(
                "2026-11-27T06:00:00.0Z  INFO unison::network::quic: New QUIC connection from: [::1]:1",
                id: 20
            )
        )
        #expect(isGearLibraryNoise(noise))
        let clock = try #require(
            parseGearLogLine(
                #"2026-11-27T06:24:41.8Z  INFO lnx_trace: FWD | F8 dir="dev→app" device=keystage app=ladyland port=Keystage KBD/CTRL kind="clock""#,
                id: 21
            )
        )
        let sensing = try #require(
            parseGearLogLine(
                #"2026-11-27T06:24:41.9Z  INFO lnx_trace: FWD | FE dir="dev→app" device=keystage app=ladyland port=Keystage KBD/CTRL kind="active-sensing""#,
                id: 22
            )
        )
        #expect(isGearClockRow(try #require(gearTraceRow(clock))))
        #expect(isGearClockRow(try #require(gearTraceRow(sensing))))
        #expect(gearLogMatches(clock, query: "keystage"))
        #expect(!gearLogMatches(clock, query: "maru"))
    }
}
