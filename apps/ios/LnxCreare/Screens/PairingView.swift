import SwiftUI

/// LAN の LNX とのペアリング。サーバの出す QR を読む（読めない機械では同じ文字列を貼る）
struct PairingView: View {
    /// 待っているサーバ（Bonjour のインスタンス名）。nil なら誰でもよい
    let serverName: String?
    let onPaired: (PairingCode) -> Void
    /// ペアリングをやめて戻る（前の pin が残っているときだけ渡す）
    var onCancel: (() -> Void)?

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
            if let onCancel {
                Button("戻る", action: onCancel)
                    .font(.footnote)
                    .tint(.white.opacity(0.7))
                    .accessibilityIdentifier("pairing.cancel")
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
        LinkLog.note("pairing: 受け取った（\(scanned.utf8.count) バイト、待っているのは \(serverName ?? "誰でも")）")
        do {
            onPaired(try PairingCode.accept(scanned, for: serverName))
        } catch .otherServer(let other) {
            LinkLog.note("pairing: 別のサーバの QR（\(other)）")
            problem = "別のサーバ（\(other)）の QR です"
        } catch {
            LinkLog.note("pairing: 読めない（\(error)）")
            problem = "ペアリングの QR ではありません"
        }
    }
}

#Preview {
    ZStack {
        Backdrop()
        PairingView(serverName: "lnx-mac", onPaired: { _ in })
    }
    .preferredColorScheme(.dark)
}
