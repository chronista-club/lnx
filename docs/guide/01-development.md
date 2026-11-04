# 01. 開発の回し方

> **Status**: Draft（Status log 参照）
> **Related**: [design 01](../design/01-lnx-server-link.md)（接続の設計、テストの三層）、[design 02](../design/02-architecture.md)（構成）、[apps/ios/README.md](../../apps/ios/README.md)、[README.md](../../README.md)
> **対象**: `.mise.toml`, `tasks/`, `rust-toolchain.toml`, `Cargo.toml`, `apps/ios/project.yml`

## Overview

Rust の workspace（`crates/`）と Apple のアプリ（`apps/ios`）を、**mise のタスク**で回す。
タスクの実体は `tasks/` 以下の Ruby（mise の file task）。一覧は `mise tasks ls`。

| タスク | 何をするか |
|---|---|
| `mise run server:run` | LNX サーバをこの Mac で起動（`[::]:12730`、Bonjour `_lnx._udp`）。一覧は `crates/lnx-server/lnx-server.example.toml`。`LNX_SERVER_CONFIG` で差し替え。常駐中なら止まって案内する |
| `mise run server:install` | LNX サーバを launchd（ユーザーの LaunchAgent）で常駐させる。ログイン中は落ちても立ち上がり直す |
| `mise run server:restart` | 常駐しているサーバを作り直して立て直す（build → 実行ファイルを写す → `kickstart -k`） |
| `mise run server:logs` | 常駐しているサーバのログを追う（`~/Library/Logs/lnx-server.log`） |
| `mise run server:status` | 常駐の様子（launchd の状態、pid、待ち受け、ログの最後） |
| `mise run server:uninstall` | 常駐をやめる（`bootout` → plist を消す。実行ファイル・ログ・設定は残す） |
| `mise run server:test [args]` | `cargo test -p lnx-server`（実 QUIC の往復を含む）と、常駐タスクの組み立てのテスト（Ruby）。引数はそのまま cargo test へ |
| `mise run ios:gen` | `apps/ios/project.yml` から `LnxCreare.xcodeproj` を生成（XcodeGen） |
| `mise run ios:test` | Swift Testing の単体テスト + UI テスト（既定は iPad シミュレータ） |
| `mise run ios:run` | シミュレータを起こし、ビルド → インストール → 起動 |
| `mise run mac:run` | Mac 版をビルドして開く（同じターゲットの macOS destination） |

`ios:test` / `ios:run` / `mac:run` は `ios:gen` に依存するので、プロジェクトの生成は自動で走る。

## Prerequisites

- **Rust**: `rust-toolchain.toml` が 1.99.1（rustfmt / clippy 込み）を指す。rustup が入っていれば `cargo` を打つだけで揃う。
  **mise には rust を書かない**（design 02「分岐の答え」）
- **mise**: `.mise.toml` が `xcodegen` / `gh` / `pre-commit` を入れる（`mise install`）。`RUST_LOG=info`、`RUST_BACKTRACE=1` も mise の env
- **Xcode 27 以上**（iOS 27 SDK）。シミュレータの既定は `iPad Pro 11-inch (M5)` / iOS 27.2（`LNX_IOS_SIM` / `LNX_IOS_OS`）。
  同名の端末が runtime ごとにあるので OS も指定する。Simulator.app が無い Mac でも `simctl` だけで動く
- **club-unison**: Rust は crates.io の `club-unison` 2.2、Swift は Swift Package（`exactVersion: 2.2.0`）。どちらも初回ビルドで取れる
- 低遅延のオーディオ I/F は推奨だが、サーバと lnx creare の接続には要らない（音はまだ出ない）

## Usage

### Rust

```bash
cargo build                 # workspace 全体
cargo test                  # 全 crate のテスト
cargo fmt && cargo clippy   # 整形と lint（commit 前）

# lnx-engine のデモ。workspace は virtual manifest なので -p が要る
cargo run -p lnx-engine --example beatmachine_demo               # ビートマシン
cargo run -p lnx-engine --example beatmachine_demo_with_samples  # samples/ にテスト音源を作って鳴らす
cargo run -p lnx-engine --example simple_tone_test               # エンジン経由でトーンを出す
cargo run -p lnx-engine --example audio_debug_test               # エンジンの初期化と出力の確認
cargo run -p lnx-engine --example raw_audio_test                 # エンジンを通さず CPAL を直に叩く

# lnx コマンド。サブコマンドは揃っているがハンドラの大半は TODO で、表示は固定値
cargo run -p lnx-cli -- --help
cargo run -p lnx-cli -- status
```

### LNX サーバ

```bash
mise run server:run                               # 既定: example.toml の一覧つき
LNX_SERVER_CONFIG=my.toml mise run server:run     # 設定を差し替える

# 直接
cargo run -p lnx-server -- --config crates/lnx-server/lnx-server.example.toml
cargo run -p lnx-server -- --addr '[::]:12730' --name lnx-mac --no-mdns
```

`mise run server:run` は、同じポート（`LNX_SERVER_ADDR`、既定 12730）で待ち受けている古い lnx-server を止めてから起動する。lnx-server 以外のプロセスがポートを握っていたら止めずに終わる。
サーバは手元用（ペアリング）の待ち受けも `[::1]:12731` に立てる。Mac 版 lnx creare がここからペアリング URL を取って QR を出す。ターミナルに QR を出したいときは `--qr`。
`--addr` / `--config` は環境変数 `LNX_SERVER_ADDR` / `LNX_SERVER_CONFIG` でも渡せる。名乗りの確認は `dns-sd -B _lnx._udp`。
偽サーバが要るときは club-unison の `unison` CLI で `unison mock --schema crates/lnx-server/schemas/lnx.kdl --addr '[::1]:12730'`（心拍は出さない）。
サーバは SIGTERM / SIGINT（Ctrl-C）で畳んで抜け、Bonjour の goodbye を出す（幽霊を残さない）。

### 常駐させる（launchd）

ふだんの開発機では、サーバを launchd のユーザー LaunchAgent で常駐させる。端末や Claude のバックグラウンドで立てると、
端末を閉じる・セッションの時間切れ・VP の立て直しで一緒に消える。

```bash
mise run server:install     # build → 実行ファイルを写す → plist を書く → bootstrap → 待ち受けを確かめる
mise run server:status      # launchd の状態、pid、12730 / 12731 の待ち受け、ログの最後
mise run server:logs        # tail -F ~/Library/Logs/lnx-server.log
mise run server:restart     # コードを変えたら。build → 実行ファイルを差し替える → kickstart -k
mise run server:uninstall   # 常駐をやめる
```

| 置き場 | 中身 |
|---|---|
| `~/Library/LaunchAgents/club.chronista.lnx-server.plist` | LaunchAgent（`RunAtLoad` + `KeepAlive`）。引数は install のときの env で決まる |
| `~/.local/share/lnx-server/bin/lnx-server` | 常駐が指す実行ファイル。`target/` はビルドのたびに変わり、mbx では symlink の先なので、写したものを指す。差し替えは rename（走っているプロセスを壊さない） |
| `~/Library/Application Support/club.chronista.lnx-server/lnx-server.toml` | 設定（既知サーバの一覧）。無ければ install が example から写す。あれば触らない（手で直した一覧を消さない） |
| `~/Library/Application Support/club.chronista.lnx-server/{cert,key}.pem` | 証明書。`server:run` と同じ既定の置き場なので、ペアリング済みの pin はそのまま |
| `~/Library/Logs/lnx-server.log` | stdout / stderr（色の制御文字は入れない） |

- 引数を変えて入れる: `LNX_SERVER_ADDR` / `LNX_SERVER_LOCAL_ADDR` / `LNX_SERVER_CONFIG` / `LNX_SERVER_STATE` / `LNX_SERVER_NAME` / `LNX_SERVER_NO_MDNS=1` を付けて `server:install`。
  plist の中身が変わるので、`server:restart` ではなく install し直す。restart / status / uninstall は env ではなく、入っている plist の引数を見る
- 試験は別のラベルで。plist・実行ファイル・ログの置き場はラベルから分かれる。port・名乗り・証明書の置き場も本番と分けないと install が断る
  （本番の 12730 / 12731、`LNX_SERVER_NAME` も `LNX_SERVER_NO_MDNS=1` も無い、`LNX_SERVER_STATE` が無い、のどれでも止まる）:
  `LNX_SERVER_LABEL=club.chronista.lnx-server.test LNX_SERVER_ADDR='[::]:12740' LNX_SERVER_LOCAL_ADDR='[::1]:12741' LNX_SERVER_STATE=/tmp/lnx-agent-test LNX_SERVER_NAME=lnx-agent-test mise run server:install`。
  restart / status / logs / uninstall にも同じ `LNX_SERVER_LABEL` を付ける（引数は入っている plist から読む）
- `server:run` / `server:install` が古いサーバを止めるとき、LaunchAgent が管理している lnx-server は止めずに案内する（止めても `KeepAlive` で立ち上がり直す）
- タスクは macOS 付属の Ruby（2.6）でも動く（mise は Ruby を入れない）。`ruby tasks/_lib/test/agent_test.rb` が組み立てのテスト
- 常駐中に `server:run` は使わない。古いサーバを止めても `KeepAlive` で立ち上がり直して取り合うので、`server:run` は案内を出して止まる。端末で回したいときは先に `server:uninstall`
- 初めて install すると、macOS の「ログイン項目」（バックグラウンド項目）に lnx-server が載る
- **ローカルネットワークの許可は lnx-server 自身に掛かる**（端末から立てたときは端末のアプリの許可を使う）。
  初めての起動では、判定がつくまでの数秒、Wi-Fi（en0）からの問い合わせに答えない（lo0 と iPad の USB 共有 bridge100 は答える。2026-11-04 実測）。
  そのあとも LAN から見つからなければ「システム設定 → プライバシーとセキュリティ → ローカルネットワーク」で lnx-server を許可する

### lnx creare（iOS / macOS）

```bash
mise run ios:run                              # iPad シミュレータ
mise run mac:run                              # Mac 版
LNX_IOS_SIM="iPhone 17" mise run ios:test     # 端末を変える

# Xcode で開く
cd apps/ios && xcodegen generate && open LnxCreare.xcodeproj
```

`LnxCreare.xcodeproj` は生成物で git 管理外。ターゲットや設定は `project.yml` を直して生成し直す。
ファイルを足すときはディレクトリに置けば次の生成で拾われる。

### 通しで動かす

```bash
mise run server:run          # ターミナル 1
mise run ios:run             # ターミナル 2 → 同じ Mac の LNX につながり、心拍が脈打つ
mise run ios:test            # UI テストはサーバが居るときだけ走る（居なければ skip）
```

シミュレータと Mac 版は同じ機械の `[::1]:12730` にも直結する。実機は Bonjour で探す（iPhone / iPad で確認済み 2026-11-04、design 01）。

### 実機（iPhone / iPad）に入れる

署名チームは `3EQKG4B352`（ANYCREATIVE, K.K.）。端末はロックを解除し、USB か同じ Wi-Fi で Mac から見える状態にする。

```bash
cd apps/ios
xcodebuild -project LnxCreare.xcodeproj -scheme LnxCreare -destination 'id=<UDID>' \
  -allowProvisioningUpdates -derivedDataPath build-device build   # 初回は端末をチームに登録する
xcrun devicectl device install app --device <UDID> build-device/Build/Products/Debug-iphoneos/LnxCreare.app
xcrun devicectl device process launch --device <UDID> club.chronista.lnx.creare
```

UDID は `xcrun devicectl list devices` で見る。「LNX を探しています」のまま止まるときは、端末の設定でローカルネットワークの許可を確認する（design 01 の「やってはいけない」）。

### 変更の流れ

- 既定ブランチは `master`、開発は `nightly` に積む。作業ブランチは `nightly` から切る（`CONTRIBUTING.md` は `main` と書いているが、実際の既定は `master`）
- 設計に触れる変更は、同じ PR で `docs/design` を触る（[docs/README.md](../README.md) の書き方）
- 長く走るプロセス（`server:run` など）を Claude Code から起こすときは ichimi 経由（`.claude/CLAUDE.md`）。
  LNX サーバを置いておくだけなら `server:install` で常駐させる（Claude のバックグラウンドは時間切れで殺される）
- CI にビルド・テストは無い（`.github/workflows` は Issue / PR の自動アサインだけ）。手元で `cargo test` と `mise run ios:test` を通す

## Troubleshooting

| 症状 | 原因と対処 |
|---|---|
| `mise run` のたびにツールの auto_install が走り、`cargo-edit` が rustc の版で止まる | `.mise.toml` の `[tools]` に cargo 系を書かない（2026-11-04 に外した）。Rust は rustup に任せる |
| 「iOS 27.2 のシミュレータ runtime が無い」 | `xcrun simctl list runtimes` で入っている OS を見て `LNX_IOS_OS` を合わせる（27.0 の runtime は "path not found" で起動できない。`xcodebuild -downloadPlatform iOS` で Xcode に合う runtime を入れる） |
| 端末名が合っているのに見つからない | 同名の端末が runtime ごとにある。`LNX_IOS_SIM` と `LNX_IOS_OS` の両方を指定する |
| UI テストが skip される | LNX サーバが居ない。`mise run server:run` を立ててから `mise run ios:test` |
| Hello の応答が decode できず timeout | `lnx.kdl` と `LnxProtocol.swift` がズレている。codegen は無いので手で揃える（design 01） |
| Bonjour で名乗らない | `--no-mdns` を付けていないか確認し、`dns-sd -B _lnx._udp` で見る。広告に失敗しても警告を出して続行する |
| 同じ Mac の `dns-sd -L` / `-G` で、lo0 など一部の NIC にしか出ない | 同じ Mac の mDNSResponder は、どれか 1 つの NIC の答えが新しいうちは他の NIC で問い直さないので、キャッシュの見え方だけで欠けることがある。名乗っているかは別の端末（iPad など）か、en0 から直接問って確かめる |
| `server:run` が「LaunchAgent で常駐している」と言って止まる | 常駐中（`server:status`）。作り直すなら `server:restart`、端末で回すなら先に `server:uninstall` |
| 常駐させたのに iPad が Wi-Fi で見つけない | lnx-server 自身のローカルネットワークの許可を確かめる（上の「常駐させる」）。`server:logs` に `bonjour: … を広告` が出ているかも見る |
| 常駐が立ち上がらない（`server:install` が「立ち上がらない」で止まる） | 出てきたログの最後を見る。ポートを別のプロセスが握っていれば `KeepAlive` が 10 秒おきに立て直し続けるので、`server:status` の待ち受けで握っている pid を探す |
| 音が出ない | `lnx audio list` は固定値を返すだけ（TODO）。`cargo run -p lnx-engine --example audio_debug_test` と `raw_audio_test` で出力デバイスを確かめる |

## Status log

- 2026-11-04: LNX サーバの常駐（launchd）を足した。`server:install` / `restart` / `logs` / `status` / `uninstall`、`server:run` は常駐中なら止まる。
  試験用ラベル（12740 / 12741）で install → kill -9 から立ち上がり直す → restart → uninstall（goodbye を確認）まで通した。本番の install はまだ
- 2026-11-04: Draft。`README.md`、`apps/ios/README.md`、`tasks/`、`.mise.toml`、`rust-toolchain.toml` から事実を集めて起こした。
  手順の通しは design 01 の確認（2026-11-03 / 04）に依る。README の `cargo run --bin lnx -- devices` と環境変数
  `LNX_AUDIO_DEVICE` / `LNX_BUFFER_SIZE` はコードに無いので載せていない
