# 01. 開発の回し方

> **Status**: Draft（Status log 参照）
> **Related**: [design 01](../design/01-lnx-server-link.md)（接続の設計、テストの三層）、[design 02](../design/02-architecture.md)（構成）、[apps/ios/README.md](../../apps/ios/README.md)、[README.md](../../README.md)
> **対象**: `.mise.toml`, `tasks/`, `rust-toolchain.toml`, `Cargo.toml`, `apps/ios/project.yml`

## Overview

Rust の workspace（`crates/`）と Apple のアプリ（`apps/ios`）を、**mise のタスク**で回す。
タスクの実体は `tasks/` 以下の Ruby（mise の file task）。一覧は `mise tasks ls`。

| タスク | 何をするか |
|---|---|
| `mise run server:run` | LNX サーバをこの Mac で起動（`[::]:12730`、Bonjour `_lnx._udp`）。一覧は `crates/lnx-server/lnx-server.example.toml`。`LNX_SERVER_CONFIG` で差し替え |
| `mise run server:test [args]` | `cargo test -p lnx-server`（実 QUIC の往復を含む）。引数はそのまま cargo test へ |
| `mise run ios:gen` | `apps/ios/project.yml` から `LnxCreare.xcodeproj` を生成（XcodeGen） |
| `mise run ios:test` | Swift Testing の単体テスト + UI テスト（既定は iPad シミュレータ） |
| `mise run ios:run` | シミュレータを起こし、ビルド → インストール → 起動 |
| `mise run mac:run` | Mac 版をビルドして開く（同じターゲットの macOS destination） |

`ios:test` / `ios:run` / `mac:run` は `ios:gen` に依存するので、プロジェクトの生成は自動で走る。

## Prerequisites

- **Rust**: `rust-toolchain.toml` が 1.99.1（rustfmt / clippy 込み）を指す。rustup が入っていれば `cargo` を打つだけで揃う。
  **mise には rust を書かない**（design 02「分岐の答え」）
- **mise**: `.mise.toml` が `xcodegen` / `gh` / `pre-commit` を入れる（`mise install`）。`RUST_LOG=info`、`RUST_BACKTRACE=1` も mise の env
- **Xcode 27 以上**（iOS 26 SDK）。シミュレータの既定は `iPad Pro 11-inch (M5)` / iOS 26.5（`LNX_IOS_SIM` / `LNX_IOS_OS`）。
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

`--addr` / `--config` は環境変数 `LNX_SERVER_ADDR` / `LNX_SERVER_CONFIG` でも渡せる。名乗りの確認は `dns-sd -B _lnx._udp`。
偽サーバが要るときは club-unison の `unison` CLI で `unison mock --schema crates/lnx-server/schemas/lnx.kdl --addr '[::1]:12730'`（心拍は出さない）。

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

シミュレータと Mac 版は同じ機械の `[::1]:12730` にも直結する。実機は Bonjour で探す（実機での確認は未）。

### 変更の流れ

- 既定ブランチは `master`、開発は `nightly` に積む。作業ブランチは `nightly` から切る（`CONTRIBUTING.md` は `main` と書いているが、実際の既定は `master`）
- 設計に触れる変更は、同じ PR で `docs/design` を触る（[docs/README.md](../README.md) の書き方）
- 長く走るプロセス（`server:run` など）を Claude Code から起こすときは ichimi 経由（`.claude/CLAUDE.md`）
- CI にビルド・テストは無い（`.github/workflows` は Issue / PR の自動アサインだけ）。手元で `cargo test` と `mise run ios:test` を通す

## Troubleshooting

| 症状 | 原因と対処 |
|---|---|
| `mise run` のたびにツールの auto_install が走り、`cargo-edit` が rustc の版で止まる | `.mise.toml` の `[tools]` に cargo 系を書かない（2026-11-04 に外した）。Rust は rustup に任せる |
| 「iOS 26.5 のシミュレータ runtime が無い」 | `xcrun simctl list runtimes` で入っている OS を見て `LNX_IOS_OS` を合わせる（27.0 の runtime は 2026-11-03 時点で "path not found" だった） |
| 端末名が合っているのに見つからない | 同名の端末が runtime ごとにある。`LNX_IOS_SIM` と `LNX_IOS_OS` の両方を指定する |
| UI テストが skip される | LNX サーバが居ない。`mise run server:run` を立ててから `mise run ios:test` |
| Hello の応答が decode できず timeout | `lnx.kdl` と `LnxProtocol.swift` がズレている。codegen は無いので手で揃える（design 01） |
| Bonjour で名乗らない | `--no-mdns` を付けていないか確認し、`dns-sd -B _lnx._udp` で見る。広告に失敗しても警告を出して続行する |
| 音が出ない | `lnx audio list` は固定値を返すだけ（TODO）。`cargo run -p lnx-engine --example audio_debug_test` と `raw_audio_test` で出力デバイスを確かめる |

## Status log

- 2026-11-04: Draft。`README.md`、`apps/ios/README.md`、`tasks/`、`.mise.toml`、`rust-toolchain.toml` から事実を集めて起こした。
  手順の通しは design 01 の確認（2026-11-03 / 04）に依る。README の `cargo run --bin lnx -- devices` と環境変数
  `LNX_AUDIO_DEVICE` / `LNX_BUFFER_SIZE` はコードに無いので載せていない
