import SwiftUI

/// LNX 自身の画面。心拍が脈打ち、知っているサーバが並ぶ
struct LnxHomeView: View {
    let supervisor: LinkSupervisor
    #if os(macOS)
    @State private var offeringPairing = false
    #endif

    var body: some View {
        VStack(spacing: 24) {
            header
            #if os(macOS)
            // Mac 版だけ: iPad に読ませるペアリングの QR を出す（裁定 mem_1CggiZeAYrK7rqz3VNpszU）
            Button("iPad をペアリング") { offeringPairing = true }
                .accessibilityIdentifier("home.pairIPad")
                .sheet(isPresented: $offeringPairing) {
                    PairingOfferView { offeringPairing = false }
                }
            #endif
            Spacer()
            Pulse(seq: supervisor.heartbeat?.seq ?? 0)
            Text(heartbeatLine)
                .accessibilityIdentifier("home.heartbeat")
                .font(.footnote.monospaced())
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            serverList
            if supervisor.canUnpair {
                // 動作確認と、サーバを入れ替えたとき用。pin を消してペアリング画面へ
                Button("ペアリングを解除") { supervisor.unpair() }
                    .font(.footnote)
                    .tint(.white.opacity(0.5))
                    .accessibilityIdentifier("home.unpair")
            }
        }
        .padding(32)
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
                            Image(systemName: "chevron.right")
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
