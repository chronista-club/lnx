import SwiftUI
import Testing
@testable import LnxCreare

/// Phosphor Icons（使う SVG だけを取り込んだもの）。メニュー項目には小さく描き直したテンプレート画像を渡す
@Suite("Icon")
@MainActor
struct IconTests {
    @Test("取り込んだアイコンは全部、Assets にテンプレートとしてある", arguments: Phosphor.allCases)
    func everyIconIsInAssets(_ icon: Phosphor) throws {
        #if os(macOS)
        let image = try #require(NSImage(named: icon.rawValue))
        #expect(image.isTemplate)
        #else
        let image = try #require(UIImage(named: icon.rawValue))
        #expect(image.renderingMode == .alwaysTemplate)
        #endif
    }

    @Test("メニュー用は指定の大きさで描き直す（Phosphor の素の大きさ 256 で出さない）")
    func menuImageIsSmall() throws {
        let image = try #require(Icon.renderMenuImage(.linkBreak, size: 18))
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("メニュー用は白紙ではない（素材が欠けていない）", arguments: Phosphor.allCases)
    func menuImageIsNotBlank(_ icon: Phosphor) throws {
        let image = try #require(Icon.renderMenuImage(icon, size: 18))
        #expect(try opaquePixels(image) > 0)
    }

    @Test("メニュー用は一度だけ描く（心拍のたびに描き直さない）")
    func menuImageIsCached() throws {
        let first = try #require(Icon.renderMenuImage(.qrCode, size: 18))
        let second = try #require(Icon.renderMenuImage(.qrCode, size: 18))
        #expect(first === second)
    }

    private func opaquePixels(_ image: PlatformImage) throws -> Int {
        #if os(macOS)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #else
        let cgImage = try #require(image.cgImage)
        #endif
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
    }
}
