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

    /// 最初につなぐ先。見つかっていればそれ。シミュレータと Mac は同じ機械の localhost も候補
    var preferred: LinkTarget? {
        if let first = found.first { return first }
        #if targetEnvironment(simulator) || os(macOS)
        return .localDaemon(port: LnxDefaults.port)
        #else
        return nil
        #endif
    }

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: LnxDefaults.bonjourType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.resolve(results) }
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

    /// service endpoint を host:port に解く（UDP の "接続" は path 解決だけで ready になる）
    private func resolve(_ results: Set<NWBrowser.Result>) {
        for result in results where resolving[result.endpoint] == nil {
            let connection = NWConnection(to: result.endpoint, using: .udp)
            resolving[result.endpoint] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard case .ready = state, let connection else { return }
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                    let name = Self.hostString(host)
                    Task { @MainActor in
                        self?.add(.host(name, port: port.rawValue))
                    }
                }
                connection.cancel()
            }
            connection.start(queue: .main)
        }
    }

    private func add(_ target: LinkTarget) {
        if !found.contains(target) { found.append(target) }
    }

    /// IPv6 の "%en0" のような scope は落とす（UnisonClient は角括弧なしの literal を取る）
    nonisolated static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): "\(address)"
        case .ipv6(let address): "\(address)".split(separator: "%").first.map(String.init) ?? "\(address)"
        case .name(let name, _): name
        @unknown default: "\(host)"
        }
    }
}
