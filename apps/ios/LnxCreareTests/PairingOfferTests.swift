import CoreImage
import Foundation
import Testing
@testable import LnxCreare

/// Mac 版が出すペアリングの QR — 手元の LNX から URL を取り、QR にする
@Suite("PairingOffer")
struct PairingOfferTests {
    let url = "lnx://pair?v=1&name=lnx-mac&cert=\(PairingCodeTests.certText)"

    @Test("取った URL を確かめ、QR にする")
    func loads() async throws {
        let offer = try await PairingOffer.load(from: FakePairingSource(info: PairingInfo(url: url, name: "lnx-mac", cert: PairingCodeTests.certText)))
        #expect(offer.serverName == "lnx-mac")
        #expect(offer.url == url)
    }

    @Test("アプリが読めない URL は QR にしない")
    func rejectsUnreadableURL() async {
        let source = FakePairingSource(info: PairingInfo(url: "lnx://pair?v=1&name=lnx-mac&cert=MPv_PgE", name: "lnx-mac", cert: "MPv_PgE"))
        await #expect(throws: PairingCode.ParseError.self) { try await PairingOffer.load(from: source) }
    }

    @Test("QR を読み戻すと同じ URL になる")
    func qrRoundTrip() throws {
        let image = try #require(PairingOffer.qrImage(for: url))
        #expect(image.width >= 200)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        #expect(features.first?.messageString == url)
    }
}

struct FakePairingSource: PairingSource {
    let info: PairingInfo
    func fetch() async throws -> PairingInfo { info }
}
