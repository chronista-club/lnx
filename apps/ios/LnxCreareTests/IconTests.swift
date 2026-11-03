import PhosphorSwift
import SwiftUI
import Testing
@testable import LnxCreare

/// Phosphor Icons の使い方 — メニュー項目には小さく描き直したテンプレート画像を渡す
@Suite("Icon")
@MainActor
struct IconTests {
    @Test("メニュー用は指定の大きさで描き直す（Phosphor の素の大きさ 256 で出さない）")
    func menuImageIsSmall() throws {
        let image = try #require(Icon.renderMenuImage(.linkBreak, size: 18))
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("メニュー用はテンプレート（メニューの文字色に染まる）")
    func menuImageIsTemplate() throws {
        let image = try #require(Icon.renderMenuImage(.qrCode, size: 18))
        #if os(macOS)
        #expect(image.isTemplate)
        #else
        #expect(image.renderingMode == UIImage.RenderingMode.alwaysTemplate)
        #endif
    }
}
