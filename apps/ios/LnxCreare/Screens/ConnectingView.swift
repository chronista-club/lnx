import SwiftUI

/// つながるまでの画面。何をしているかだけ、静かに
struct ConnectingView: View {
    let state: LinkState
    let target: LinkTarget?
    /// ペアリングをやり直す（LAN の先のときだけ出す）
    var onRepair: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Text(AppInfo.name)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .foregroundStyle(.white)
            ProgressView()
                .tint(.white.opacity(0.7))
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if let target {
                Text(target.displayName)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white.opacity(0.4))
            }
            if case .host? = target, case .reconnecting = state {
                // pin が合わない（サーバの証明書が変わった）と、ここで回り続ける
                Button("ペアリングし直す", action: onRepair)
                    .font(.footnote)
                    .tint(.white.opacity(0.7))
                    .accessibilityIdentifier("connecting.repair")
            }
        }
        .padding()
    }

    private var message: String {
        switch state {
        case .idle:
            "lnx を探しています"
        case .connecting(let attempt):
            attempt <= 1 ? "lnx につないでいます" : "lnx につないでいます（\(attempt) 回目）"
        case .reconnecting(let attempt, let delay):
            "つなぎ直します（\(attempt) 回目、\(delay.formatted(.units(allowed: [.seconds], fractionalPart: .hide))) 後）"
        case .connected:
            "つながりました"
        case .needsPairing:
            "ペアリングが要ります"
        }
    }
}
