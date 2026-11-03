# lnx creare（iOS）

LNX への入り口となるネイティブアプリ。[spec 02](../../docs/spec/02-creare.md) が言う
「Native UI = SwiftUI + Rust」の Apple 側の器で、まず iOS から始める。

## 前提

- Xcode 27 以上（iOS 26 SDK）
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
mise run mac:run             # Mac 版をビルドして開く（同じターゲットの macOS destination）
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
│   ├── Link/                   # LNX への常時接続（LinkSupervisor、UnisonLnxTransport、LnxFinder、LnxProtocol）
│   ├── Screens/                # 画面（RootView、Connecting、LnxHome、RemoteServer、ScreenRoute）
│   ├── Model/AppInfo.swift     # 表示名・タグライン・版
│   └── Resources/Assets.xcassets
├── LnxCreareTests/             # 単体テスト（Swift Testing）
└── LnxCreareUITests/           # 画面切り替えの UI テスト（実サーバが居るときだけ。無ければ skip）
```

## 決めたこと

| 項目 | 値 | 理由 |
|---|---|---|
| 表示名 / ターゲット | lnx creare / `LnxCreare` | Bevy 版 `crates/lnx-creare` と同じ看板 |
| bundle id | `club.chronista.lnx.creare` | 過去の Apple アプリ（LNXX / Sizma）の `club.chronista.` に揃え、`lnx.` 配下で増やせるようにした |
| Team | `3EQKG4B352`（ANYCREATIVE, K.K.） | 実機へ入れるチーム。iPad に先に入っていたビルドと揃えた（2026-11-04） |
| 対応 OS | iOS 26.0 以上、macOS 26.0 以上 | 一つのターゲットで iOS と macOS（`supportedDestinations`）。Mac は同じ機械の localhost も接続候補 |
| メイン開発機 | iPad（iPhone も `TARGETED_DEVICE_FAMILY` に残す） | ユーザー指定（2026-11-03）。iPad は 4 方向すべて対応（Stage Manager 前提） |
| 言語 | Swift 6 言語モード、strict concurrency complete | 新規なので最初から |
| UI / テスト | SwiftUI / Swift Testing | spec の Native UI 方針、XCTest より軽い |
| プロジェクト管理 | XcodeGen | `.pbxproj` を手で触らない。差分がレビューできる |

## 次にやること

1. **Rust コアの接続** — `crates/lnx-engine` は `staticlib` と cbindgen のヘッダを既に出している。
   iOS 向けにクロスビルドして xcframework にし、spec どおり UniFFI で Swift の型を生成する
2. **「Open and Create」の最初の一歩** — マイク入力 → FFT → 画面が動く、までを 3 秒以内に
3. **macOS / visionOS** — `project.yml` の `supportedDestinations` で同じコードベースに足す
