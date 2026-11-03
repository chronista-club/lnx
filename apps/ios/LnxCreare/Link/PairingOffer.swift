import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UnisonClient

/// ペアリング URL の取り先。実物は同じ Mac の LNX の手元用 listener（[::1]:12731、lnx-local.kdl）
protocol PairingSource: Sendable {
    func fetch() async throws -> PairingInfo
}

/// Mac 版が出すペアリングの QR（裁定 mem_1CggiZeAYrK7rqz3VNpszU）。
/// 取った URL はアプリ自身の PairingCode で読めることを確かめてから出す
struct PairingOffer: Equatable, Sendable {
    var serverName: String
    var url: String

    static func load(from source: some PairingSource) async throws -> PairingOffer {
        let info = try await source.fetch()
        let code = try PairingCode(parsing: info.url)
        return PairingOffer(serverName: code.serverName, url: info.url)
    }

    /// QR の画像。モジュール 1 つを scale 倍に拡大する（ぼかさない）
    static func qrImage(for text: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// 実物。ループバックなので検証は飛ばす（証明書は LAN 側と同じ保存済みの自己署名）
struct LocalPairingSource: PairingSource {
    var port: UInt16 = LnxDefaults.localPort

    func fetch() async throws -> PairingInfo {
        let connection = try await withTimeout(seconds: 5) { [port] in
            try await UnisonClient.connect(to: .localDaemon(port: port), trust: .skipVerify)
        }
        do {
            let channel = try await withTimeout(seconds: 3) {
                try await connection.openChannel(PairingChannel())
            }
            let info = try await withTimeout(seconds: 3) { try await channel.request(GetPairing()) }
            await connection.disconnect()
            return info
        } catch {
            await connection.disconnect()
            throw error
        }
    }
}
