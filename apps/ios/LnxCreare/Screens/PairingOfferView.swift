import SwiftUI

/// Mac 版: 同じ Mac の LNX からペアリング URL を取り、QR を出す。iPad はこれをカメラで読む
struct PairingOfferView: View {
    var source: any PairingSource = LocalPairingSource()
    let onClose: () -> Void

    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case ready(PairingOffer, CGImage)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("iPad をペアリング")
                .font(.system(size: 28, weight: .light, design: .rounded))
            switch phase {
            case .loading:
                ProgressView()
                    .frame(width: 320, height: 320)
            case .ready(let offer, let image):
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 320, height: 320)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("pairing.qr")
                Text("iPad の lnx creare で「LNX とペアリング」を開き、この QR を読んでください（\(offer.serverName)）")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Text(offer.url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: 380)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(width: 320, height: 320)
                Button("もう一度") { Task { await load() } }
            }
            Button("閉じる", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .task { await load() }
    }

    private func load() async {
        phase = .loading
        do {
            let offer = try await PairingOffer.load(from: source)
            guard let image = PairingOffer.qrImage(for: offer.url) else {
                phase = .failed("QR を作れませんでした")
                return
            }
            phase = .ready(offer, image)
        } catch {
            LinkLog.note("pairing offer: \(error)")
            phase = .failed("この Mac の LNX（手元用 [::1]:\(LnxDefaults.localPort)）からペアリング情報を取れませんでした。\nサーバが新しいコードで動いているか確かめてください")
        }
    }
}
