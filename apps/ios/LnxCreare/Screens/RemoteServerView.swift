import SwiftUI

/// 相手の画面（汎用）。今は名前だけ出す素通しの窓 — ここに kind ごとの画面が入る
struct RemoteServerView: View {
    let server: RemoteServer
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Label("LNX", systemImage: "chevron.left")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("remote.back")
                Spacer()
            }
            Spacer()
            Text(server.name)
                .accessibilityIdentifier("remote.title")
                .font(.system(size: 40, weight: .light, design: .rounded))
                .foregroundStyle(.white)
            Text(server.kind)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
            Text(server.endpointLabel)
                .font(.footnote.monospaced())
                .foregroundStyle(.white.opacity(0.4))
            Text("この窓はまだ素通し。ここに \(server.kind) の画面が入る")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 24)
            Spacer()
        }
        .padding(32)
    }
}
