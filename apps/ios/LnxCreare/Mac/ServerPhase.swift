#if os(macOS)
import ServiceManagement

/// 同梱した lnx-server の登録（SMAppService.Status の写し）
enum Registration: Equatable, Sendable {
    case enabled
    /// システム設定 › ログイン項目 で許可を待っている
    case requiresApproval
    case notRegistered
    /// .app に plist が無い（ビルドの欠陥）
    case notFound

    /// 一度も登録していない同梱 agent は .notFound を返す（midistage の実測 2026-10-11）。
    /// plist が .app にあれば「未登録」、無ければ壊れたビルド
    init(_ status: SMAppService.Status, plistInBundle: Bool) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = plistInBundle ? .notRegistered : .notFound
        @unknown default: self = .notFound
        }
    }
}

/// launchd の上の今。`launchctl print` の一段目（タブ 1 つ）から拾う（tasks/_lib/agent.rb の parse_state と同じ読み方）
struct LaunchdJob: Equatable, Sendable {
    var state: String?
    var pid: Int32?
    /// 前の終わり方。シグナルなら "last terminating signal"、exit なら "last exit code"
    var lastExit: String?

    var isRunning: Bool { state == "running" && pid != nil }

    static func parse(_ output: String) -> LaunchdJob {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") where line.hasPrefix("\t") && !line.hasPrefix("\t\t") {
            let body = line.dropFirst()
            guard let separator = body.range(of: " = ") else { continue }
            let key = String(body[..<separator.lowerBound])
            if fields[key] == nil { fields[key] = String(body[separator.upperBound...]) }
        }
        return LaunchdJob(
            state: fields["state"],
            pid: fields["pid"].flatMap { Int32($0) },
            lastExit: fields["last terminating signal"] ?? fields["last exit code"]
        )
    }
}

/// メニューバーに出す LNX サーバの今。登録・launchd・server:install の常駐の 3 つから決める
enum ServerPhase: Equatable, Sendable {
    case running(pid: Int32)
    /// 登録済みだが走っていない（落ちて立て直しを待っている、など）
    case stopped(lastExit: String?)
    /// 常駐していない（未登録）
    case off
    case requiresApproval
    /// server:install（#38 の素の LaunchAgent）が入っている。同じラベルなので、走っているのはそちら
    case legacy(running: Bool)
    /// このビルドに lnx-server が入っていない
    case broken

    static func resolve(registration: Registration, job: LaunchdJob?, legacyInstalled: Bool) -> ServerPhase {
        if legacyInstalled { return .legacy(running: job?.isRunning ?? false) }
        switch registration {
        case .notFound: return .broken
        case .notRegistered: return .off
        case .requiresApproval: return .requiresApproval
        case .enabled:
            if let job, job.isRunning, let pid = job.pid { return .running(pid: pid) }
            return .stopped(lastExit: job?.lastExit)
        }
    }

    /// メニューバーのアイコンが「動いている」になるか
    var isRunning: Bool {
        switch self {
        case .running: true
        case .legacy(let running): running
        case .stopped, .off, .requiresApproval, .broken: false
        }
    }

    var title: String {
        switch self {
        case .running(let pid): "LNX サーバ — 動いています（pid \(pid)）"
        case .stopped: "LNX サーバ — 止まっています"
        case .off: "LNX サーバ — 常駐していません"
        case .requiresApproval: "LNX サーバ — ログイン項目の許可待ち"
        case .legacy(let running): running ? "LNX サーバ — server:install の常駐で動いています" : "LNX サーバ — server:install の常駐が入っています"
        case .broken: "LNX サーバ — このビルドに入っていません"
        }
    }

    var detail: String? {
        switch self {
        case .running: nil
        case .stopped(let lastExit):
            // 一度も終わっていない・正常終了は、言うことが無い
            if let lastExit, lastExit != "0", lastExit != "(never exited)" { "前の終わり方: \(lastExit)" } else { nil }
        case .off: "開始すると、ログイン時にも立ち上がります"
        case .requiresApproval: "システム設定 › 一般 › ログイン項目 で lnx creare を許可してください"
        case .legacy: "メニューから動かすには、先に mise run server:uninstall で外してください"
        case .broken: "mise run mac:run でビルドし直してください"
        }
    }
}
#endif
