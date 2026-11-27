import Foundation
import Network
import Observation

/// LAN 上の LNX サーバを Bonjour（_lnx._udp）で探す。
/// シミュレータでは同じ Mac の localhost に直接つなぐ（design 01）
@MainActor
@Observable
final class LnxFinder {
    /// 解けた先（IPv4 が前）。Bonjour から消えた service の先は忘れる
    var found: [LinkTarget] { ledger.targets }
    private var ledger = FoundTargets()
    private var browser: NWBrowser?
    private var resolving: [NWEndpoint: NWConnection] = [:]
    /// 今 Bonjour に出ている service（解決の試し直しはここに居るものだけ）
    private var advertised: Set<NWEndpoint> = []
    /// service ごとの名乗り（TXT の name、無ければインスタンス名）。pin の鍵
    private var names: [NWEndpoint: String] = [:]
    private var lastRefresh: ContinuousClock.Instant?
    /// stop のたびに進める。作り直しを待つタスクは、間に stop されていたら何もしない
    private var generation = 0
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
        // 今の先は名前で照合する（解き直しでアドレスだけ変わることがある。名前が無ければそのもので）
        if let current, let same = found.first(where: { Self.isSameServer($0, current) }) { return same }
        return found.first
    }

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        // TXT も受け取る（name = サーバの名乗り。Bonjour が「(2)」に改名しても QR の name と合う）
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: LnxDefaults.bonjourType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            LinkLog.note("bonjour: \(results.count) 件 \(results.map { "\($0.endpoint)" })")
            Task { @MainActor in self?.resolve(results) }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            LinkLog.note("bonjour browser: \(state)")
            // 失敗した browser は戻らない（ネットワークの変化、あとからの許可など）。作り直す
            if case .failed = state, let browser {
                Task { @MainActor in self?.restart(after: browser) }
            }
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
        names.removeAll()
        // 作り直したら全部解き直す（古いアドレスを持ち越さない）
        ledger = FoundTargets()
        generation += 1
    }

    private func restart(after failed: NWBrowser) {
        guard browser === failed else { return }
        stop()
        let generation = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resolveRetry)
            // 待つ間に誰かが stop（窓が消えた）か start していたら、何もしない
            guard let self, self.generation == generation, self.browser == nil else { return }
            self.start()
        }
    }

    /// browse の結果が変わった。消えた service は忘れ、新しい service を解く。
    /// service endpoint を host:port に解く（UDP の "接続" は path 解決だけで ready になる）。
    /// まず IPv4 で解く（link-local の IPv6 は scope が要り、端末によって扱いが違う）。だめなら IPv6 も許す
    private func resolve(_ results: Set<NWBrowser.Result>) {
        guard browser != nil else { return }
        advertised = Set(results.map(\.endpoint))
        names = Dictionary(
            results.compactMap { result in Self.serverName(result.endpoint, metadata: result.metadata).map { (result.endpoint, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        ledger.retain(only: advertised)
        for (endpoint, connection) in resolving where !advertised.contains(endpoint) {
            connection.cancel()
            resolving[endpoint] = nil
        }
        // 解けている先も解き直す。Bonjour の名前はそのままでも、経路が変わる（USB を抜いた、Wi-Fi が変わった）と
        // 前のアドレスは届かない。新しいアドレスが解けるまで、帳簿の前のアドレスは残す（2026-11-23 の実機の例）
        for endpoint in Self.endpointsToResolve(advertised: advertised, resolving: Set(resolving.keys)) {
            resolve(endpoint, ipv4Only: true)
        }
        LinkLog.note("found: \(found.map(\.displayName))")
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
                    LinkLog.note("resolved: \(endpoint) → \(address):\(port.rawValue) (ipv4Only=\(ipv4Only))")
                    Task { @MainActor in self?.resolved(endpoint, connection, address: address, port: port.rawValue) }
                } else {
                    LinkLog.note("resolved: \(endpoint) → remoteEndpoint 無し (ipv4Only=\(ipv4Only))")
                    Task { @MainActor in self?.retryLater(endpoint, connection, ipv4Only: !ipv4Only) }
                }
            case .failed(let error):
                LinkLog.note("resolve failed: \(endpoint) \(error) (ipv4Only=\(ipv4Only))")
                Task { @MainActor in self?.retryLater(endpoint, connection, ipv4Only: !ipv4Only, after: ipv4Only ? .zero : Self.resolveRetry) }
            case .waiting(let error):
                LinkLog.note("resolve waiting: \(endpoint) \(error) (ipv4Only=\(ipv4Only))")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    /// 広告されている先を解き直す（つなぎ直しが続けて失敗しているとき。経路が変わってアドレスが古い恐れ）。
    /// 連打しないよう resolveRetry に一度まで
    func refresh() {
        guard browser != nil else { return }
        let clock = ContinuousClock()
        if let last = lastRefresh, clock.now - last < Self.resolveRetry { return }
        lastRefresh = clock.now
        let targets = Self.endpointsToResolve(advertised: advertised, resolving: Set(resolving.keys))
        guard !targets.isEmpty else { return }
        LinkLog.note("refresh: \(targets.count) 件を解き直す")
        for endpoint in targets { resolve(endpoint, ipv4Only: true) }
    }

    /// browse の結果が変わったときに解く先: 広告されているもののうち、いま解いていないもの全部（解けているものも含む）
    nonisolated static func endpointsToResolve(advertised: Set<NWEndpoint>, resolving: Set<NWEndpoint>) -> Set<NWEndpoint> {
        advertised.subtracting(resolving)
    }

    /// 期限までに解けなかった。IPv4 だけで刺さったなら次は IPv6 も許す（交互に試す）
    private func giveUpIfStuck(_ endpoint: NWEndpoint, _ connection: NWConnection, ipv4Only: Bool) {
        guard resolving[endpoint] === connection, connection.state != .cancelled else { return }
        LinkLog.note("resolve timeout: \(endpoint)（\(Self.resolveTimeout) で解けない。試し直す）")
        retryLater(endpoint, connection, ipv4Only: !ipv4Only)
    }

    /// この試行を畳み、まだ広告されていれば間を置いて試し直す。
    /// 失敗・remoteEndpoint 無し・刺さり、のどれで終わっても同じ道を通す（試行中の印を残さない）
    private func retryLater(_ endpoint: NWEndpoint, _ connection: NWConnection, ipv4Only: Bool, after delay: Duration = resolveRetry) {
        guard resolving[endpoint] === connection else { return }
        connection.cancel()
        resolving[endpoint] = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.browser != nil, self.advertised.contains(endpoint), self.resolving[endpoint] == nil else { return }
            self.resolve(endpoint, ipv4Only: ipv4Only)
        }
    }

    /// 解けた。この試行がまだ生きていて、service が広告されている間だけ帳簿に載せる
    private func resolved(_ endpoint: NWEndpoint, _ connection: NWConnection, address: String, port: UInt16) {
        guard resolving[endpoint] === connection else { return }
        connection.cancel()
        resolving[endpoint] = nil
        guard browser != nil, advertised.contains(endpoint) else { return }
        ledger.set(.host(address, port: port, name: names[endpoint] ?? Self.serviceName(endpoint)), for: endpoint)
        LinkLog.note("found: \(found.map(\.displayName))")
    }

    /// 同じサーバか。LAN の先は名前で比べる（アドレスは経路で変わる）
    nonisolated static func isSameServer(_ a: LinkTarget, _ b: LinkTarget) -> Bool {
        if case .host(_, _, let nameA?) = a, case .host(_, _, let nameB?) = b { return nameA == nameB }
        return a == b
    }

    /// Bonjour のインスタンス名（例 lnx-mac）
    nonisolated static func serviceName(_ endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    /// サーバの名乗り（pin の鍵）。TXT の name（#33、QR の name と同じ値）を使い、無ければインスタンス名
    nonisolated static func serverName(_ endpoint: NWEndpoint, metadata: NWBrowser.Result.Metadata) -> String? {
        if case .bonjour(let txt) = metadata, let name = txt["name"], !name.isEmpty { return name }
        return serviceName(endpoint)
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

/// 解けた先の帳簿（service ごとに 1 つ）。並びは IPv4 が前、同じ族の中は見つかった順
struct FoundTargets {
    private var entries: [(endpoint: NWEndpoint, target: LinkTarget)] = []

    var targets: [LinkTarget] {
        let all = entries.map(\.target)
        return all.filter { !Self.isIPv6($0) } + all.filter(Self.isIPv6)
    }

    func contains(_ endpoint: NWEndpoint) -> Bool {
        entries.contains { $0.endpoint == endpoint }
    }

    /// 同じ service が解け直したら置き換える（アドレスが変わった）
    mutating func set(_ target: LinkTarget, for endpoint: NWEndpoint) {
        if let index = entries.firstIndex(where: { $0.endpoint == endpoint }) {
            entries[index].target = target
        } else {
            entries.append((endpoint, target))
        }
    }

    /// 広告から消えた service の先を忘れる
    mutating func retain(only advertised: Set<NWEndpoint>) {
        entries.removeAll { !advertised.contains($0.endpoint) }
    }

    private static func isIPv6(_ target: LinkTarget) -> Bool {
        if case .host(let host, _, _) = target { return host.contains(":") }
        return false
    }
}
