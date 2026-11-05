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

/// 12730 / 12731 で待ち受けているプロセス。launchd の外のものが握っていると、常駐の lnx-server は bind に失敗して落ち続ける
struct PortListener: Equatable, Sendable {
    var pid: Int32
    var command: String

    /// `lsof -nP -F pcn -iUDP:…` の出力から、待ち受けているものだけを拾う（tasks/_lib/lnx.rb の listener_pids と同じ読み方）。
    /// n 行が "a->b" のソケットは相手の決まったクライアント（Mac 版 lnx creare など）なので除く
    static func parse(_ output: String) -> [PortListener] {
        var found: [PortListener] = []
        var pid: Int32?
        var command = ""
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = value
            case "n":
                if let pid, !value.contains("->"), !found.contains(where: { $0.pid == pid }) {
                    found.append(PortListener(pid: pid, command: command))
                }
            default:
                break
            }
        }
        return found
    }

    /// 常駐自身ではない待ち受け（いちばん先のもの）
    static func foreign(in listeners: [PortListener], job: LaunchdJob?) -> PortListener? {
        listeners.first { $0.pid != job?.pid }
    }
}

/// メニューから LNX サーバに対してできること
enum ServerAction: Equatable, Sendable {
    /// 登録（済みなら登録し直し）
    case start
    /// 登録の解除。許可待ちのときは「登録をやめる」
    case stop
    case restart
    /// システム設定 › ログイン項目
    case openLoginItems
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
    /// 常駐が走っていないのに、launchd の外のプロセスが待ち受けを握っている（端末の server:run など）。
    /// このまま開始すると KeepAlive で落ち続ける（2026-11-05 の事故）。登録済み（enabled）なら今まさに落ち続けている。
    /// 許可待ちなら launchd はまだ起こしていないが、許可すると落ち続ける
    case portTaken(PortListener, registration: Registration)

    static func resolve(
        registration: Registration, job: LaunchdJob?, legacyInstalled: Bool, listeners: [PortListener] = []
    ) -> ServerPhase {
        if legacyInstalled { return .legacy(running: job?.isRunning ?? false) }
        if registration == .notFound { return .broken }
        if registration == .enabled, let job, job.isRunning, let pid = job.pid { return .running(pid: pid) }
        if let holder = PortListener.foreign(in: listeners, job: job) {
            return .portTaken(holder, registration: registration)
        }
        switch registration {
        case .notRegistered: return .off
        case .requiresApproval: return .requiresApproval
        case .enabled, .notFound: return .stopped(lastExit: job?.lastExit)
        }
    }

    /// メニューに出す操作（server:install の常駐と壊れたビルドは、案内だけで動かさない）
    var actions: [ServerAction] {
        switch self {
        case .running: [.stop, .restart]
        case .stopped, .off: [.start]
        case .requiresApproval: [.openLoginItems, .stop]
        // 握っている側を止めるまで開始しない。登録があれば、常駐（許可待ちなら登録）をやめることだけはできる
        case .portTaken(_, let registration): registration == .notRegistered ? [] : [.stop]
        case .legacy, .broken: []
        }
    }

    /// 「停止」の項目の文言。許可待ちのときは、まだ動いていないので「登録をやめる」
    var stopTitle: String {
        switch self {
        case .requiresApproval, .portTaken(_, .requiresApproval): "登録をやめる"
        default: "停止（ログイン時にも立ち上げない）"
        }
    }

    /// メニューバーのアイコンが「動いている」になるか
    var isRunning: Bool {
        switch self {
        case .running: true
        case .legacy(let running): running
        case .stopped, .off, .requiresApproval, .broken, .portTaken: false
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
        case .portTaken(let holder, _): "LNX サーバ — \(holder.command)（pid \(holder.pid)）が待ち受けを握っています"
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
        case .portTaken(_, .enabled):
            "握っているあいだ、常駐は 10 秒おきに立ち上がっては落ちます。端末の mise run server:run なら Ctrl-C で止めてください（常駐をやめるなら「停止」）"
        case .portTaken(_, .requiresApproval):
            "ログイン項目で許可すると立ち上がりますが、握られているあいだは落ち続けます。端末の mise run server:run なら Ctrl-C で止めてから許可してください"
        case .portTaken:
            "端末の mise run server:run なら Ctrl-C で止めてから「開始」してください"
        }
    }
}
#endif
