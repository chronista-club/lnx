# lnx creare（iOS）

LNX への入り口となるネイティブアプリ。[spec 02](../../docs/spec/02-creare.md) が言う
「Native UI = SwiftUI + Rust」の Apple 側の器で、まず iOS から始める。

## 前提

- Xcode 27 以上（iOS 27 SDK）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen` か `mise install`）

## 使い方

```bash
cd apps/ios
xcodegen generate            # project.yml → LnxCreare.xcodeproj（git 管理外）
open LnxCreare.xcodeproj     # Xcode で開いて Run

# コマンドラインから（リポジトリのどこからでも）
mise run ios:gen             # 生成だけ
mise run ios:test            # テスト（Swift Testing + UI テスト、既定は iPad シミュレータ）
mise run ios:run             # シミュレータで起動
mise run mac:run             # Mac 版をビルドして開く（同じターゲットの macOS destination。lnx-server を同梱）
mise run mac:install         # Mac 版を ~/Applications に入れて開く（LNX サーバの常駐はここから登録）
mise run mac:test            # Mac 版の単体テスト（LnxCreareMacTests。共有の LnxCreareTests も Mac で回す）
```

メイン開発機は iPad。`ios:test` の既定端末は iPad Pro 11-inch (M5)（`.mise.toml` の `LNX_IOS_SIM`）。
別の端末で走らせるなら `LNX_IOS_SIM="iPhone 17" mise run ios:test`。

`.xcodeproj` は生成物。ターゲットや設定を変えるときは `project.yml` を編集して生成し直す。
Xcode 上でファイルを追加した場合も、ディレクトリに置けば次の生成で拾われる。

## LNX サーバとつなぐ

```bash
mise run server:run          # 別ターミナルで LNX サーバ（Mac、[::]:12730）
mise run ios:run             # シミュレータで起動 → localhost の LNX につながり、心拍が脈打つ
```

シミュレータは同じ Mac の `[::1]:12730` に直結する。実機は Bonjour（`_lnx._udp`）で探す（iPhone / iPad で確認済み 2026-11-04）。
接続の設計は [docs/design/01-lnx-server-link.md](../../docs/design/01-lnx-server-link.md)。

## 構成

```
apps/ios/
├── project.yml                 # XcodeGen 定義（これが正）
├── LnxCreare/                  # アプリ本体
│   ├── App/LnxCreareApp.swift  # エントリポイント
│   ├── Link/                   # LNX への常時接続（LinkSupervisor、UnisonLnxTransport、LnxFinder、LnxProtocol、ペアリングと pin: PairingCode・PinStore・LinkTrust）
│   ├── Screens/                # 画面（RootView、Connecting、Pairing、QRScanner、LnxHome、RemoteServer、ScreenRoute）
│   ├── Mac/                    # Mac 版だけ: メニューバーの LNX と、同梱 lnx-server の常駐（SMAppService）
│   ├── Model/AppInfo.swift     # 表示名・タグライン・版
│   └── Resources/Assets.xcassets
├── LnxCreareTests/             # 単体テスト（Swift Testing）
├── LnxCreareMacTests/          # Mac 版だけの単体テスト（host は Mac 版。LnxCreareTests も一緒に回す）
├── LaunchAgents/               # Mac 版に同梱する LaunchAgent の plist
├── scripts/embed-lnx-server.sh # Mac 版のビルドで lnx-server を .app に入れて署名する（project.yml の postBuildScripts）
└── LnxCreareUITests/           # 画面切り替えの UI テスト（実サーバが居るときだけ。無ければ skip）
```

## 決めたこと

| 項目 | 値 | 理由 |
|---|---|---|
| 表示名 / ターゲット | lnx creare / `LnxCreare` | Bevy 版 `crates/lnx-creare` と同じ看板 |
| bundle id | `club.chronista.lnx.creare` | 過去の Apple アプリ（LNXX / Sizma）の `club.chronista.` に揃え、`lnx.` 配下で増やせるようにした |
| Team | `3EQKG4B352`（ANYCREATIVE, K.K.） | 有償チーム。iPad に先に入っていたビルドと揃えた（2026-11-04）。Personal Team の `J627YTC8NE`（無料）は、入れるたびに端末で開発元の信頼が要り、プロファイルも 7 日で切れるので使わない |
| 対応 OS | iOS 27.0 以上、macOS 27.0 以上 | 最新の OS に揃える（mako の裁定 2026-11-04。手元の iPhone / iPad / Mac はすべて 27）。一つのターゲットで iOS と macOS（`supportedDestinations`）。Mac は同じ機械の localhost も接続候補 |
| メイン開発機 | iPad（iPhone も `TARGETED_DEVICE_FAMILY` に残す） | ユーザー指定（2026-11-03）。iPad は 4 方向すべて対応（Stage Manager 前提） |
| 言語 | Swift 6 言語モード、strict concurrency complete | 新規なので最初から |
| アイコン | [Phosphor Icons](https://github.com/phosphor-icons/swift)（2.1.0 の regular から、使う SVG だけを `Assets.xcassets/Phosphor/` に取り込む。MIT、`Resources/Phosphor-LICENSE.txt`） | mako の裁定（2026-11-04、`mem_1Cggjxznnx1u4qGDwjftB6`）。パッケージは素材が約 9,000 個で、Release でも iOS 64MB / Mac 95MB になった（取り込みで 9.8MB / 10MB）。SF Symbols は使わない。呼ぶのは `Icon.view` / メニュー項目は `Icon.menuImage`。足す手順は `Screens/Icon.swift` の頭 |
| UI / テスト | SwiftUI / Swift Testing | spec の Native UI 方針、XCTest より軽い |
| プロジェクト管理 | XcodeGen | `.pbxproj` を手で触らない。差分がレビューできる |

## 次にやること

1. **Rust コアの接続** — `crates/lnx-engine` は `staticlib` と cbindgen のヘッダを既に出している。
   iOS 向けにクロスビルドして xcframework にし、spec どおり UniFFI で Swift の型を生成する
2. **「Open and Create」の最初の一歩** — マイク入力 → FFT → 画面が動く、までを 3 秒以内に
3. **macOS / visionOS** — `project.yml` の `supportedDestinations` で同じコードベースに足す
