import SwiftUI

/// LAN の LNX とのペアリング。サーバの出す QR を読む（読めない機械では同じ文字列を貼る）
struct PairingView: View {
    /// 待っているサーバ（Bonjour のインスタンス名）。nil なら誰でもよい
    let serverName: String?
    let onPaired: (PairingCode) -> Void

    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("LNX とペアリング")
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white)
            Text(guide)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            #if os(iOS)
            if QRScannerView.isSupported {
                QRScannerView { accept($0) }
                    .frame(maxWidth: 420, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            #endif
            HStack {
                TextField("lnx://pair?… を貼り付け", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.footnote.monospaced())
                    .autocorrectionDisabled()
                    .onSubmit { accept(text) }
                    .accessibilityIdentifier("pairing.code")
                Button("ペアリング") { accept(text) }
                    .disabled(text.isEmpty)
                    .accessibilityIdentifier("pairing.submit")
            }
            .frame(maxWidth: 520)
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }

    private var guide: String {
        if let serverName {
            "「\(serverName)」が起動時に出す QR を読んでください。\nはじめてつなぐ LNX は、本物かどうかをこれで確かめます"
        } else {
            "LNX が起動時に出す QR を読んでください"
        }
    }

    private func accept(_ scanned: String) {
        do {
            onPaired(try PairingCode.accept(scanned, for: serverName))
        } catch .otherServer(let other) {
            problem = "別のサーバ（\(other)）の QR です"
        } catch {
            problem = "ペアリングの QR ではありません"
        }
    }
}

#Preview {
    ZStack {
        Backdrop()
        PairingView(serverName: "lnx-mac") { _ in }
    }
    .preferredColorScheme(.dark)
}
