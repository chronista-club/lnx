import Foundation

/// アプリの看板。表示名とタグラインの唯一の出どころ。
enum AppInfo {
    /// 表示名。Bevy 版 `crates/lnx-creare` のウィンドウタイトルと揃える
    static let name = "lnx creare"
    /// README の結びの一文
    static let tagline = "Build the wave, Feel the experience"
    /// Hello で名乗る版（MARKETING_VERSION）
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
