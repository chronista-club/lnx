import SwiftUI

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

/// 使う Phosphor Icons（裁定 mem_1Cggjxznnx1u4qGDwjftB6）。パッケージは素材が約 9,000 個あり、アプリが 54〜84MB
/// 膨らむので、使う SVG だけを `Assets.xcassets/Phosphor/` に取り込んだ（mako の裁定「取り込んじゃっていいよ」）。
/// 取り込み元は phosphor-icons/swift 2.1.0 の regular、MIT（`Resources/Phosphor-LICENSE.txt`）。
/// 足すときは同じ版の `Sources/PhosphorSwift/Resources/Assets.xcassets/SVG/<name>.imageset/<name>.svg` を
/// 同じ形の imageset（template、ベクタを保つ）で置き、ここに case を足す
enum Phosphor: String, CaseIterable, Sendable {
    case caretLeft = "caret-left"
    case caretRight = "caret-right"
    case dotsThreeCircle = "dots-three-circle"
    case linkBreak = "link-break"
    case qrCode = "qr-code"

    /// 素材は template なので foregroundStyle で染まる
    var image: Image { Image(rawValue).resizable() }
}

@MainActor
enum Icon {
    /// 画面に置くアイコン。label があれば読み上げる名前、無ければ飾り（読み上げない）
    static func view(_ icon: Phosphor, size: CGFloat, label: String? = nil) -> some View {
        icon.image
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel(label.map { Text($0) } ?? Text(""))
            .accessibilityHidden(label == nil)
    }

    /// メニュー項目のアイコン。メニュー（UIMenu / NSMenu）は Image を素の大きさで出す（Phosphor は 256 単位）ので、
    /// 小さく描き直したテンプレート画像を渡す
    static func menuImage(_ icon: Phosphor, size: CGFloat = 18) -> Image {
        guard let image = renderMenuImage(icon, size: size) else { return icon.image }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }

    /// 一度だけ描いて覚える（画面は心拍のたびに組み直され、Menu の中身もそのたびに作られる）
    private static var rendered: [String: PlatformImage] = [:]

    static func renderMenuImage(_ icon: Phosphor, size: CGFloat) -> PlatformImage? {
        let key = "\(icon.rawValue)@\(size)"
        if let hit = rendered[key] { return hit }
        let renderer = ImageRenderer(content: view(icon, size: size))
        renderer.scale = 3
        #if os(macOS)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        #else
        guard let image = renderer.uiImage?.withRenderingMode(.alwaysTemplate) else { return nil }
        #endif
        rendered[key] = image
        return image
    }
}
