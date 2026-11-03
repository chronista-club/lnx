import SwiftUI

/// つながるまでの画面。何をしているかだけ、静かに
struct ConnectingView: View {
    let state: LinkState
    let target: LinkTarget?

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
        }
        .padding()
    }

    private var message: String {
        switch state {
        case .idle:
            "LNX を探しています"
        case .connecting(let attempt):
            attempt <= 1 ? "LNX につないでいます" : "LNX につないでいます（\(attempt) 回目）"
        case .reconnecting(let attempt, let delay):
            "つなぎ直します（\(attempt) 回目、\(delay.formatted(.units(allowed: [.seconds], fractionalPart: .hide))) 後）"
        case .connected:
            "つながりました"
        }
    }
}
