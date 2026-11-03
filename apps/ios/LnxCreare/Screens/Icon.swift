import PhosphorSwift
import SwiftUI

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

/// アイコンは Phosphor Icons（裁定 mem_1Cggjxznnx1u4qGDwjftB6）。素材は template なので foregroundStyle で染まる
@MainActor
enum Icon {
    /// 画面に置くアイコン。Phosphor の Image は resizable なので大きさを決めて置く
    static func view(_ icon: Ph, size: CGFloat) -> some View {
        icon.regular
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    /// メニュー項目のアイコン。メニュー（UIMenu / NSMenu）は Image を素の大きさで出す（Phosphor は 256 単位）ので、
    /// 小さく描き直したテンプレート画像を渡す
    static func menuImage(_ icon: Ph, size: CGFloat = 18) -> Image {
        guard let image = renderMenuImage(icon, size: size) else { return Image(systemName: "circle") }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }

    static func renderMenuImage(_ icon: Ph, size: CGFloat) -> PlatformImage? {
        let renderer = ImageRenderer(content: view(icon, size: size))
        renderer.scale = 3
        #if os(macOS)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
        #else
        return renderer.uiImage?.withRenderingMode(.alwaysTemplate)
        #endif
    }
}
