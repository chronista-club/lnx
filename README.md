# lnx

lnx - wavelet synthesize engine

## 概要

lnx(リンクスと発音)は、**Low-Latency, High-Quality, Human-Friendly** をモットーとした、audio/visual表現のためのライブツールプロジェクトです。

> **開発状況**: 現在、初期開発段階にあります。

### プロジェクトビジョン

#### 機能
- audio/vision/fieldに働きかける
- インプット/アクションフロー/アウトプット

#### 目指す主要機能

- **超低遅延**: リアルタイムパフォーマンスに最適化
- **高品質**: プロフェッショナルグレードのオーディオ・ビジュアル処理
- **直感的操作**: 人間中心のインターフェースデザイン
- **マルチプラットフォーム**: Apple ecosystem全体で統一された体験

## 現在の実装状況

### 実装済み機能
- ✅ 基本的なSwiftUIアプリケーション構造
- ✅ macOSネイティブアプリケーションとしての基盤
- ✅ テストフレームワーク（Swift Testing）の設定

### 開発中機能
- 🚧 オーディオファイル再生機能
- 🚧 基本的なUI/UXデザイン

### 計画中機能
- ⏳ リアルタイムオーディオ処理
- ⏳ ビジュアルエフェクト機能
- ⏳ MIDI機器連携
- ⏳ マルチチャンネル入出力サポート

## 対応機器

### 公式対応MIDI機器
- **Akai LPD8** - MIDI 1.0対応パッドコントローラー
- **[Korg Keystage](https://www.korg.com/jp/products/computergear/keystage/)** - MIDI 2.0対応キーボードコントローラー
  - 高解像度ベロシティ（16ビット）対応
  - Per-Note Controllerサポート
  - 双方向通信による設定同期

### 動作確認済み機器
- その他のMIDI 1.0/2.0準拠デバイス（基本機能のみ）

## 技術要件

### システム要件
- **macOS 15.5以上** (Sequoia以降)
- Apple Silicon Mac推奨（Intel Macでも動作可能）
- 最小メモリ: 8GB RAM（推奨: 16GB以上）
- ストレージ: 1GB以上の空き容量

### 開発環境
- **Xcode 16.0以上**
- **Swift 6.0以上**
- **Git** (Git LFS推奨)

### 使用フレームワーク
#### 現在使用中
- SwiftUI
- Swift Testing Framework

#### 将来的に使用予定
- Core Audio
- AVFoundation
- Metal Performance Shaders
- Combine

## セットアップ

### 1. リポジトリのクローン

```bash
# 通常のクローン
git clone git@github.com:chronista/lnx-experience.git
cd lnx-experience

# 大容量ファイルを扱う場合（推奨）
git lfs install
git clone git@github.com:chronista/lnx-experience.git
cd lnx-experience
```

> **注意**: プロジェクトには大容量のWAVファイル（約304MB）が含まれています。Git LFSの使用を推奨します。

### 2. Git LFSの設定（推奨）

```bash
# Git LFSをインストール（Homebrewを使用）
brew install git-lfs

# リポジトリでGit LFSを初期化
git lfs install

# 大容量ファイルの追跡設定
git lfs track "*.wav"
git lfs track "*.aiff"
git add .gitattributes
git commit -m "Configure Git LFS for audio files"
```

### 3. Xcodeでプロジェクトを開く

```bash
open sizma/sizma.xcodeproj
```

### 4. 開発チーム設定

1. Xcodeでプロジェクトを開く
2. プロジェクトナビゲータで「sizma」を選択
3. 「Signing & Capabilities」タブを選択
4. 「Team」ドロップダウンから開発チームを選択
   - 個人開発の場合: Personal Team を選択
   - 組織開発の場合: 該当する Developer Team を選択

### 5. ビルドと実行

```bash
# コマンドラインからビルド
xcodebuild -project sizma/sizma.xcodeproj -scheme sizma build

# またはXcodeから
# Cmd + R でビルドと実行
```

## プロジェクト構造

```
lnx-experience/
├── README.md               # プロジェクトドキュメント
├── .gitignore             # Git除外設定
├── .gitattributes         # Git LFS設定（推奨）
└── sizma/
    ├── sizma.xcodeproj/    # Xcodeプロジェクトファイル
    ├── sizma/              # メインアプリケーション
    │   ├── Assets.xcassets/    # アプリアイコン、カラー設定
    │   ├── Assets/            # オーディオファイル（WAV）
    │   │   ├── 20250802_145427.wav  # (201MB)
    │   │   └── 20250802_160053.wav  # (103MB)
    │   ├── sizmaApp.swift      # アプリケーションエントリポイント
    │   ├── ContentView.swift  # メインビュー
    │   └── sizma.entitlements  # App Sandbox設定
    ├── sizmaTests/         # ユニットテスト
    │   └── sizmaTests.swift
    └── sizmaUITests/       # UIテスト
        ├── sizmaUITests.swift
        └── sizmaUITestsLaunchTests.swift
```

### 今後追加予定のディレクトリ構造

```
sizma/
├── Audio/          # オーディオ処理モジュール
├── Visual/         # ビジュアル処理モジュール
├── Sync/           # 同期機能
├── Models/         # データモデル
├── ViewModels/     # MVVM ViewModels
├── Views/          # SwiftUIビュー
├── Utils/          # ユーティリティ関数
└── Resources/      # リソースファイル
```

## テスト

### ユニットテストの実行

```bash
# コマンドラインから
xcodebuild test -project sizma/sizma.xcodeproj -scheme sizma

# Xcodeから
# Cmd + U でテスト実行
```

### UIテストの実行

```bash
# コマンドラインから
xcodebuild test -project sizma/sizma.xcodeproj \
  -scheme sizma \
  -destination 'platform=macOS'

# Xcodeから
# Product > Test メニューから実行
```

## 既知の制約と注意事項

### セキュリティ（App Sandbox）
- アプリはApp Sandboxが有効になっています
- ファイルアクセスはユーザーが選択したファイルのみ（読み取り専用）
- ネットワークアクセスには追加のentitlementが必要

### 大容量ファイルの扱い
- プロジェクトには300MB超のWAVファイルが含まれています
- 初回クローン時に時間がかかる場合があります
- Git LFSの使用を強く推奨します

### macOSバージョン要件
- macOS 15.5（Sequoia）以降が必要
- 古いmacOSバージョンでは動作しません
- 最新のmacOS APIを使用しているため、後方互換性は限定的です

## トラブルシューティング

### よくある問題と解決方法

#### 1. ビルドエラー: "Signing for "sizma" requires a development team"
**解決方法**: 
- Xcodeで開発チームを設定してください（上記セットアップ手順4を参照）

#### 2. 大容量ファイルのダウンロードが遅い
**解決方法**:
```bash
# Git LFSを使用
git lfs pull

# または、オーディオファイルなしでクローン
git clone --filter=blob:none git@github.com:chronista/lnx-experience.git
```

#### 3. macOSバージョンエラー
**解決方法**:
- macOS 15.5以降にアップデートしてください
- または、プロジェクト設定で最小OSバージョンを下げることも可能（機能制限あり）

#### 4. Swift Testingフレームワークのエラー
**解決方法**:
- Xcode 16.0以降を使用していることを確認
- Swift 6.0以降が必要です

## アーキテクチャ設計原則

### 現在採用している原則
- **SwiftUI宣言的UI**: 状態駆動のUI更新
- **MVVM パターン**: View-ViewModel分離
- **Swift Concurrency**: async/awaitによる非同期処理

### 将来的に採用予定の原則
- **モジュラー設計**: 各機能を独立したモジュールとして実装
- **リアクティブプログラミング**: Combineフレームワークの活用
- **プロトコル指向**: Swiftのprotocolを活用した柔軟な設計
- **依存性注入**: テスタビリティの向上

## コントリビューション

プロジェクトへの貢献を歓迎します！

### 貢献の方法
1. このリポジトリをフォーク
2. フィーチャーブランチを作成 
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. 変更をコミット 
   ```bash
   git commit -m 'Add amazing feature'
   ```
4. ブランチにプッシュ 
   ```bash
   git push origin feature/amazing-feature
   ```
5. プルリクエストを作成

### コーディング規約
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)に従う
- SwiftLintによる自動チェック（今後導入予定）
- Swift Testingフレームワークを使用したテスト作成
- コミットメッセージは明確で簡潔に

### 問題報告
バグや機能要望は[Issues](https://github.com/chronista/lnx-experience/issues)で報告してください。

報告時に含めてほしい情報：
- macOSバージョン
- Xcodeバージョン
- 再現手順
- 期待される動作
- 実際の動作
- エラーメッセージ（ある場合）

## ロードマップ

### Phase 1: 基盤構築（現在）
- [x] プロジェクトセットアップ
- [x] 基本的なSwiftUI構造
- [x] オーディオファイル読み込み
- [x] 基本的な再生機能
- [x] MIDI 1.0デバイス対応（LPD8）
- [x] MIDI 2.0デバイス対応（Korg Keystage）

### Phase 2: コア機能実装
- [ ] リアルタイムオーディオ処理
- [ ] 基本的なエフェクト
- [ ] MIDI入力対応
- [ ] 設定管理

### Phase 3: ビジュアル機能
- [ ] オーディオビジュアライザー
- [ ] リアルタイムエフェクト
- [ ] GPU加速レンダリング

### Phase 4: 拡張機能
- [ ] プラグインシステム
- [ ] ネットワーク同期
- [ ] マルチデバイス対応

### Future Vision
- [ ] AI支援機能
- [ ] クラウド連携
- [ ] iOS/iPadOS版

## ライセンス

TBD（検討中）

## 謝辞

このプロジェクトは、音と映像の新しい表現を追求するすべてのクリエイターに捧げます。

### Special Thanks
- SwiftUIコミュニティ
- Core Audioドキュメント作成者
- オープンソースオーディオプロジェクトのコントリビューター

## お問い合わせ

- GitHub Issues: [https://github.com/chronista/lnx-experience/issues](https://github.com/chronista/lnx-experience/issues)
- Project Wiki: [https://github.com/chronista/lnx-experience/wiki](https://github.com/chronista/lnx-experience/wiki)（準備中）

---

**sizma - 静馬** - 音と映像の波を起こし、新たな体験を創造する

*Last updated: 2025-08-11*