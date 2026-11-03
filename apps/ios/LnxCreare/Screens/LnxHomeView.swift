import PhosphorSwift
import SwiftUI

/// LNX 自身の画面。心拍が脈打ち、知っているサーバが並ぶ
struct LnxHomeView: View {
    let supervisor: LinkSupervisor
    #if os(macOS)
    @State private var offeringPairing = false
    #else
    @State private var confirmingUnpair = false
    #endif

    var body: some View {
        VStack(spacing: 24) {
            header
            #if os(macOS)
            Button("iPad をペアリング") { offeringPairing = true }
                .accessibilityIdentifier("home.pairIPad")
            #endif
            Spacer()
            Pulse(seq: supervisor.heartbeat?.seq ?? 0)
            Text(heartbeatLine)
                .accessibilityIdentifier("home.heartbeat")
                .font(.footnote.monospaced())
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            serverList
            #if !os(macOS)
            // 右上のメニューと同じもの。ここにも置く（わかりやすい。裁定 2026-11-04）
            if supervisor.canUnpair {
                Button("ペアリングを解除") { confirmingUnpair = true }
                    .font(.footnote)
                    .tint(.white.opacity(0.5))
                    .accessibilityIdentifier("home.unpair")
            }
            #endif
        }
        .padding(32)
        .overlay(alignment: .topTrailing) { menu.padding(20) }
        #if os(macOS)
        .sheet(isPresented: $offeringPairing) {
            PairingOfferView { offeringPairing = false }
        }
        #else
        // 確認は一段だけ
        .confirmationDialog(unpairQuestion, isPresented: $confirmingUnpair, titleVisibility: .visible) {
            Button("解除する", role: .destructive) { supervisor.unpair() }
        } message: {
            Text("次につなぐときは、Mac 版の「iPad をペアリング」の QR を読み直します")
        }
        #endif
    }

    /// 右上のメニュー（裁定 2026-11-04。下 / 上のボタンと同じものをここにも）。Mac 版は「iPad をペアリング」（QR を出す）、
    /// iPhone / iPad は「ペアリングを解除」（pin を消して切断 → ペアリング画面）。Mac 版は手元の localhost なので解除は無い
    @ViewBuilder
    private var menu: some View {
        #if os(macOS)
        Menu {
            Button { offeringPairing = true } label: {
                Label { Text("iPad をペアリング") } icon: { Icon.menuImage(.qrCode) }
            }
        } label: {
            Icon.view(.dotsThreeCircle, size: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("home.menu")
        #else
        if supervisor.canUnpair {
            Menu {
                Button(role: .destructive) { confirmingUnpair = true } label: {
                    Label { Text("ペアリングを解除") } icon: { Icon.menuImage(.linkBreak) }
                }
            } label: {
                Icon.view(.dotsThreeCircle, size: 28)
                    .foregroundStyle(.white.opacity(0.7))
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home.menu")
        }
        #endif
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(AppInfo.name)
                .font(.system(size: 36, weight: .light, design: .rounded))
                .foregroundStyle(.white)
            if case .connected(let welcome) = supervisor.state {
                Text("\(welcome.serverName) · v\(welcome.serverVersion)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var unpairQuestion: String {
        if case .connected(let welcome) = supervisor.state { return "「\(welcome.serverName)」とのペアリングを解除しますか" }
        return "ペアリングを解除しますか"
    }

    private var heartbeatLine: String {
        guard let beat = supervisor.heartbeat else { return "心拍を待っています" }
        let seconds = beat.uptimeMs / 1000
        return "心拍 #\(beat.seq) · 起動から \(seconds / 60) 分 \(seconds % 60) 秒"
    }

    @ViewBuilder
    private var serverList: some View {
        if supervisor.servers.isEmpty {
            Text("ほかに知っているサーバはまだありません")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("場にいるサーバ")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(supervisor.servers) { server in
                    Button {
                        supervisor.selection = server
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(server.name).foregroundStyle(.white)
                                Text("\(server.kind) · \(server.endpointLabel)")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Icon.view(.caretRight, size: 16)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(14)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("server.\(server.id)")
                }
            }
            .frame(maxWidth: 520)
        }
    }
}

/// 心拍のたびにひと脈
private struct Pulse: View {
    let seq: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                .frame(width: 180, height: 180)
                .scaleEffect(seq.isMultiple(of: 2) ? 1.0 : 1.12)
            Circle()
                .fill(Color.accentColor.opacity(seq == 0 ? 0.15 : 0.6))
                .frame(width: 24, height: 24)
                .scaleEffect(seq.isMultiple(of: 2) ? 1.0 : 1.6)
        }
        .animation(.easeOut(duration: 0.6), value: seq)
    }
}
