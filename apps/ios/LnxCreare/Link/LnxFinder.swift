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

    /// 最初につなぐ先。シミュレータと Mac は同じ機械の localhost（LAN の先はペアリングが要り、
    /// シミュレータと Mac はカメラで QR を読めない）。実機は見つかった先から選ぶ
    func preferred(pins: any PinStore) -> LinkTarget? {
        #if targetEnvironment(simulator) || os(macOS)
        return .localDaemon(port: LnxDefaults.port)
        #else
        return Self.choose(from: found, pins: pins)
        #endif
    }

    /// ペアリング済みの先を優先する（LAN に別の `_lnx._udp` が居ても、そのペアリング画面に縛られない）。
    /// 無ければ先頭（IPv4 が前）
    nonisolated static func choose(from found: [LinkTarget], pins: any PinStore) -> LinkTarget? {
        let paired = found.first { target in
            guard case .host(_, _, let name?) = target else { return false }
            return pins.certificate(for: name) != nil
        }
        return paired ?? found.first
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
    }

    /// service endpoint を host:port に解く（UDP の "接続" は path 解決だけで ready になる）。
    /// まず IPv4 で解く（link-local の IPv6 は scope が要り、端末によって扱いが違う）。だめなら IPv6 も許す
    private func resolve(_ results: Set<NWBrowser.Result>) {
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
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                    let address = Self.hostString(host)
                    let name = Self.serviceName(endpoint)
                    LinkLog.note("resolved: \(endpoint) → \(address):\(port.rawValue) (ipv4Only=\(ipv4Only))")
                    Task { @MainActor in self?.add(.host(address, port: port.rawValue, name: name)) }
                } else {
                    LinkLog.note("resolved: \(endpoint) → remoteEndpoint 無し (ipv4Only=\(ipv4Only))")
                }
                connection.cancel()
            case .failed(let error):
                LinkLog.note("resolve failed: \(endpoint) \(error) (ipv4Only=\(ipv4Only))")
                connection.cancel()
                if ipv4Only {
                    Task { @MainActor in self?.resolve(endpoint, ipv4Only: false) }
                }
            case .waiting(let error):
                LinkLog.note("resolve waiting: \(endpoint) \(error) (ipv4Only=\(ipv4Only))")
            default:
                break
            }
        }
        connection.start(queue: .main)
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
