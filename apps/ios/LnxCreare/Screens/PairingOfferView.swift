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
                    .frame(width: 460, height: 460)
            case .ready(let offer, let image):
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    // version 18 前後（約 90 モジュール）なので大きく出す。iPad のカメラが離れていても読める
                    .frame(width: 460, height: 460)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("pairing.qr")
                Text("iPad の lnx creare で「LNX とペアリング」を開き、この QR を読んでください（\(offer.serverName)）")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Text(offer.url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: 460)
                Button("URL をコピー") { copy(offer.url) }
                    .font(.footnote)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(width: 460, height: 460)
                Button("もう一度") { Task { await load() } }
            }
            Button("閉じる", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .task { await load() }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
        } catch let error as PairingCode.ParseError {
            LinkLog.note("pairing offer: URL を読めない \(error)")
            phase = .failed("LNX から届いたペアリング URL をこのアプリが読めませんでした（\(error)）。\nサーバとアプリの版が合っているか確かめてください")
        } catch {
            LinkLog.note("pairing offer: \(error)")
            phase = .failed("この Mac の LNX（手元用 [::1]:\(LnxDefaults.localPort)）からペアリング情報を取れませんでした。\nサーバが新しいコードで動いているか確かめてください")
        }
    }
}
