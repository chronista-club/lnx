#if os(macOS)
import Foundation

// lnx-server のログ（~/Library/Logs/lnx-server.log）を「流れ」と「MIDI トレース」に分けて読む純粋計算層（[calculations]）。
// 行の形（tracing の fmt、ANSI なし）:
//   2026-11-27T06:32:11.558367Z  INFO lnx_server::gear::runtime: keystage: plugged in
//   2026-11-27T14:36:49.093712Z  INFO FWD | B7 4F 1F dir="dev→app" device=lpd8 app=vp port=LPD8 mk2 kind="cc"

enum GearLogLevel: String, Sendable, Equatable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

struct GearLogLine: Sendable, Equatable, Identifiable {
    var id: Int
    var time: Date
    var level: GearLogLevel
    var target: String?
    var message: String
    var fields: [String: String]
}

/// MIDI トレース表の 1 行
struct GearTraceRow: Sendable, Equatable, Identifiable {
    var id: Int
    var time: Date
    var direction: String
    var gear: String
    var app: String
    var verdict: String
    var kind: String
    var detail: String
}

private let knownTraceKeys = ["dir", "device", "gear", "app", "port", "kind", "via", "token"]

func parseGearLogLine(_ raw: String, id: Int) -> GearLogLine? {
    let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2, let time = parseGearLogTime(String(parts[0])) else { return nil }
    let rest = parts[1].drop { $0 == " " }
    let levelAndRest = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard levelAndRest.count == 2, let level = GearLogLevel(rawValue: String(levelAndRest[0])) else {
        return nil
    }
    var body = String(levelAndRest[1])

    var target: String?
    if let colon = body.range(of: ": "),
       body[..<colon.lowerBound].contains("::"),
       !body[..<colon.lowerBound].contains(" ")
    {
        target = String(body[..<colon.lowerBound])
        body = String(body[colon.upperBound...])
    }

    var marks: [(key: String, start: String.Index, valueStart: String.Index)] = []
    for key in knownTraceKeys {
        var searchFrom = body.startIndex
        while let r = body.range(of: " \(key)=", range: searchFrom..<body.endIndex) {
            marks.append((key, r.lowerBound, r.upperBound))
            searchFrom = r.upperBound
        }
    }
    marks.sort { $0.start < $1.start }
    var fields: [String: String] = [:]
    for (i, m) in marks.enumerated() {
        let end = i + 1 < marks.count ? marks[i + 1].start : body.endIndex
        var value = String(body[m.valueStart..<end]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        fields[m.key] = value
    }
    let message = marks.first.map { String(body[..<$0.start]) } ?? body
    return GearLogLine(
        id: id,
        time: time,
        level: level,
        target: target,
        message: message.trimmingCharacters(in: .whitespaces),
        fields: fields
    )
}

func parseGearLogTime(_ s: String) -> Date? {
    guard s.hasSuffix("Z"), s.count >= 20 else { return nil }
    let chars = Array(s)
    func int(_ a: Int, _ b: Int) -> Int? { Int(String(chars[a..<b])) }
    guard let y = int(0, 4), let mo = int(5, 7), let d = int(8, 10),
          let h = int(11, 13), let mi = int(14, 16), let se = int(17, 19)
    else { return nil }
    var ms = 0
    if chars.count > 21, chars[19] == "." {
        let frac = String(chars[20..<min(23, chars.count - 1)])
        ms = Int(frac.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
    }
    var c = DateComponents()
    c.year = y
    c.month = mo
    c.day = d
    c.hour = h
    c.minute = mi
    c.second = se
    c.nanosecond = ms * 1_000_000
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)
}

func isGearLibraryNoise(_ line: GearLogLine) -> Bool {
    line.target?.hasPrefix("unison") == true
}

/// トレース行か（単一の lnx-server.log に「流れ」と「トレース」が同居していても判別できる）
func isGearTraceLine(_ line: GearLogLine) -> Bool {
    if line.target == "lnx_trace" { return true }
    if line.message.hasPrefix("---- MIDI trace ") { return true }
    if line.fields["device"] != nil || line.fields["gear"] != nil || line.fields["dir"] != nil || line.fields["token"] != nil {
        return true
    }
    return false
}

func gearTraceRow(_ line: GearLogLine) -> GearTraceRow? {
    if line.message.hasPrefix("----") { return nil }
    guard isGearTraceLine(line) else { return nil }
    let pieces = line.message.components(separatedBy: " | ")
    let verdict = pieces.first ?? line.message
    let detail = pieces.dropFirst().joined(separator: " | ")
    return GearTraceRow(
        id: line.id,
        time: line.time,
        direction: line.fields["dir"] ?? "",
        gear: line.fields["gear"] ?? line.fields["device"] ?? "",
        app: line.fields["app"] ?? "",
        verdict: verdict,
        kind: line.fields["kind"] ?? "",
        detail: detail
    )
}

func gearLogMatches(_ line: GearLogLine, query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespaces)
    if q.isEmpty { return true }
    let hay = ([line.message, line.target ?? ""] + line.fields.values).joined(separator: " ")
    return hay.localizedCaseInsensitiveContains(q)
}

struct GearLineSplitter: Sendable {
    private var pending = Data()

    init() {}

    mutating func push(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            if newline > start {
                lines.append(String(decoding: pending[start..<newline], as: UTF8.self))
            }
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
        return lines
    }

    mutating func reset() {
        pending = Data()
    }
}

func newestGearLogFile(_ names: [String], prefix: String) -> String? {
    names.filter { $0 == prefix || $0.hasPrefix(prefix + ".") }.max()
}

func isGearClockRow(_ row: GearTraceRow) -> Bool {
    row.kind == "clock" || row.kind == "active-sensing"
}
#endif
