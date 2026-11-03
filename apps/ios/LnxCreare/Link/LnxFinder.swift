import Foundation
import Network
import Observation

/// LAN 上の LNX サーバを Bonjour（_lnx._udp）で探す。
/// シミュレータでは同じ Mac の localhost に直接つなぐ（design 01）
@MainActor
@Observable
final class LnxFinder {
    private(set) var found: [LinkTarget] = []
    private var browser: NWBrowser?
    private var resolving: [NWEndpoint: NWConnection] = [:]
    /// 今 Bonjour に出ている service（解決の試し直しはここに居るものだけ）
    private var advertised: Set<NWEndpoint> = []
    /// 解決を待つ上限と、試し直すまでの間。落ちたサーバの広告（幽霊）は SRV が返らず、いつまでも ready にならない。
    /// 同じ名前で本物が立ち上がっても browse の変化は来ないので、試し直さないと永遠に見つからない
    static let resolveTimeout: Duration = .seconds(5)
    static let resolveRetry: Duration = .seconds(3)

    /// 最初につなぐ先。シミュレータと Mac は同じ機械の localhost（LAN の先はペアリングが要り、
    /// シミュレータと Mac はカメラで QR を読めない）。実機は見つかった先から選ぶ
    func preferred(pins: any PinStore, current: LinkTarget?) -> LinkTarget? {
        #if targetEnvironment(simulator) || os(macOS)
        return .localDaemon(port: LnxDefaults.port)
        #else
        return Self.choose(from: found, pins: pins, current: current)
        #endif
    }

    /// 選ぶ順: ペアリング済みの先（LAN に別の `_lnx._udp` が居ても、そのペアリング画面に縛られない）→
    /// まだ見つかっている今の先（解除した直後に別のサーバへ飛ばない）→ 先頭（IPv4 が前）
    nonisolated static func choose(from found: [LinkTarget], pins: any PinStore, current: LinkTarget? = nil) -> LinkTarget? {
        let paired = found.first { target in
            guard case .host(_, _, let name?) = target else { return false }
            return pins.certificate(for: name) != nil
        }
        if let paired { return paired }
        if let current, found.contains(current) { return current }
        return found.first
    }

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: LnxDefaults.bonjourType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            LinkLog.note("bonjour: \(results.count) 件 \(results.map { "\($0.endpoint)" })")
            Task { @MainActor in self?.resolve(results) }
        }
        browser.stateUpdateHandler = { state in
            LinkLog.note("bonjour browser: \(state)")
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        for connection in resolving.values { connection.cancel() }
        resolving.removeAll()
        advertised.removeAll()
    }

    /// service endpoint を host:port に解く（UDP の "接続" は path 解決だけで ready になる）。
    /// まず IPv4 で解く（link-local の IPv6 は scope が要り、端末によって扱いが違う）。だめなら IPv6 も許す
    private func resolve(_ results: Set<NWBrowser.Result>) {
        advertised = Set(results.map(\.endpoint))
        for result in results where resolving[result.endpoint] == nil {
            resolve(result.endpoint, ipv4Only: true)
        }
    }

    private func resolve(_ endpoint: NWEndpoint, ipv4Only: Bool) {
        let parameters = NWParameters.udp
        if ipv4Only, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        resolving[endpoint] = connection
        LinkLog.note("resolving: \(endpoint) (ipv4Only=\(ipv4Only))")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resolveTimeout)
            self?.giveUpIfStuck(endpoint, connection, ipv4Only: ipv4Only)
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                    let address = Self.hostString(host)
                    let name = Self.serviceName(endpoint)
                    LinkLog.note("resolved: \(endpoint) → \(address):\(port.rawValue) (ipv4Only=\(ipv4Only))")
                    Task { @MainActor in self?.add(.host(address, port: port.rawValue, name: name)) }
                    connection.cancel()
                } else {
                    LinkLog.note("resolved: \(endpoint) → remoteEndpoint 無し (ipv4Only=\(ipv4Only))")
                    Task { @MainActor in self?.retryLater(endpoint, connection, ipv4Only: !ipv4Only) }
                }
            case .failed(let error):
                LinkLog.note("resolve failed: \(endpoint) \(error) (ipv4Only=\(ipv4Only))")
                if ipv4Only {
                    connection.cancel()
                    Task { @MainActor in self?.resolve(endpoint, ipv4Only: false) }
                } else {
                    Task { @MainActor in self?.retryLater(endpoint, connection, ipv4Only: true) }
                }
            case .waiting(let error):
                LinkLog.note("resolve waiting: \(endpoint) \(error) (ipv4Only=\(ipv4Only))")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    /// 期限までに解けなかった。IPv4 だけで刺さったなら次は IPv6 も許す（交互に試す）
    private func giveUpIfStuck(_ endpoint: NWEndpoint, _ connection: NWConnection, ipv4Only: Bool) {
        guard resolving[endpoint] === connection, connection.state != .cancelled else { return }
        LinkLog.note("resolve timeout: \(endpoint)（\(Self.resolveTimeout) で解けない。試し直す）")
        retryLater(endpoint, connection, ipv4Only: !ipv4Only)
    }

    /// この試行を畳み、まだ広告されていれば間を置いて試し直す。
    /// 失敗・remoteEndpoint 無し・刺さり、のどれで終わっても同じ道を通す（試行中の印を残さない）
    private func retryLater(_ endpoint: NWEndpoint, _ connection: NWConnection, ipv4Only: Bool) {
        guard resolving[endpoint] === connection else { return }
        connection.cancel()
        resolving[endpoint] = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resolveRetry)
            guard let self, self.browser != nil, self.advertised.contains(endpoint), self.resolving[endpoint] == nil else { return }
            self.resolve(endpoint, ipv4Only: ipv4Only)
        }
    }

    private func add(_ target: LinkTarget) {
        guard !found.contains(target) else { return }
        // IPv4 を前に（preferred は先頭を使う）
        if case .host(let h, _, _) = target, !h.contains(":") { found.insert(target, at: 0) } else { found.append(target) }
        LinkLog.note("found: \(found.map(\.displayName))")
    }

    /// Bonjour のインスタンス名（例 lnx-mac）。pin を引くキー
    nonisolated static func serviceName(_ endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    /// IPv6 は角括弧なしの literal（link-local の "%en0" は残す。scope が無いと届かない）
    nonisolated static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): "\(address)".split(separator: "%").first.map(String.init) ?? "\(address)"
        case .ipv6(let address): "\(address)"
        case .name(let name, _): name
        @unknown default: "\(host)"
        }
    }
}
