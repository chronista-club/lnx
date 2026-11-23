# lnx のドキュメント

**spec**（What & Why）/ **design**（How）/ **guide**（Usage）の 3 層。番号で呼ぶ（「spec 01」「design 02」）。
古いものは消さず [archive](archive/README.md) に Deprecated で残す。

| 層 | 答える問い | 読み手 |
|---|---|---|
| spec | 何を、なぜ | 決める人、後から経緯を知りたい人 |
| design | どう作るか | 実装する人、変更する人 |
| guide | どう使うか | 使う人 |

## spec — 何を、なぜ

| 番号 | 文書 | Status | 一行 |
|---|---|---|---|
| 01 | [lnx の本質 — すべての人のための creare](spec/01-core-concept.md) | Active | lnx（リンクス）＝機器と場をつなぐもの、名前と表記（画面と文書は小文字の lnx、識別子は変えない）、Low-Latency / High-Quality / Human-Friendly の 3 本柱、creare と vision、場の同期、道具・楽器との自然な対話 |
| 02 | [lnx creare — ヴィジョンクリエイティブツールの入り口](spec/02-creare.md) | Draft | "Open and Create"、3 つの役割と 5 つの原則、処理の流れ（構想）、UI の方針（未決）、ロードマップ |

## design — どう作るか

| 番号 | 文書 | Status | 一行 |
|---|---|---|---|
| 01 | [lnx サーバと lnx creare の常時接続](design/01-lnx-server-link.md) | Draft | Unison / QUIC の 1 本の接続。session（名乗り・心拍）と registry（一覧）、再接続、Bonjour、テストの三層 |
| 02 | [lnx の構成 — Unison の上に載せる](design/02-architecture.md) | Draft | 4 crate + Apple アプリの構成要素と現状、レイヤー、Unison の使い方、workspace と lnx-engine の型、未決（UI 技術ほか） |

## guide — どう使うか

| 番号 | 文書 | Status | 一行 |
|---|---|---|---|
| 01 | [開発の回し方](guide/01-development.md) | Draft | mise のタスク（server / ios / mac）、rust-toolchain.toml、XcodeGen、通しの動かし方、トラブルシューティング |
| 02 | [MIDI 機器 — Korg Keystage 49 と Akai LPD8](guide/02-midi-devices.md) | Draft | 2 台の MIDI 仕様（ノート / CC / SysEx）と推奨設定。lnx 側の実装はまだ無い |

## archive

[archive/README.md](archive/README.md) に一覧。Swift / SwiftUI（LNXX）時代の 12 本と PROJECT_STRUCTURE、Unison 前提の旧 ARCHITECTURE、2017 年の Domains メモ、GRAND_DESIGN の mindmap、GitHub Pages の残骸、旧 `spec/README.md`。

## 書き方（SDG）

正本は chronista-style の `spec-design-guide` スキル。要点だけ。

- **置き場**: `docs/spec|design|guide/NN-kebab.md`。次の番号は `ls docs/design | tail -1`
- **骨格**（見出し名は強制しない。この 4 つが読めれば成立）
  - spec: Abstract → Motivation → Scope（In / Out）→ Requirements
  - design: Abstract（どの spec を実装するか）→ Architecture（図は Mermaid）→ Data Model → Implementation。「関連」「やってはいけない」（実装で踏んだ地雷）を歓迎
  - guide: Overview → Prerequisites → Usage → Troubleshooting
- **ヘッダ**は git が知らないことだけ。`> **Status**: Draft | Active | Deprecated` / `> **Related**: …` / `> **対象**: <コードパス>`。Author・日付は書かない
- **末尾に `## Status log`**。書き換えより追記。大きく変わったら新しい番号を切り、旧文書は Deprecated にして Related で新番号を指す。古くなっても消さない
- **コードと同じ PR で触る**。設計に触れる変更は diff に design も載る。対象パスで引く: `grep -rl 'crates/lnx-server' docs/design`
- **What は文書、Why は memory**。裁定と却下した案は memory に原文で置き、文書は Related から memory ID を指す

### spec の心得（旧 `spec/README.md` から）

- 実装から独立して本質を書く。「何を」に焦点を当て、「どのように」は design へ
- 問いから始める（なぜこれが重要なのか）。簡潔に、一文一文に意味を持たせる。抽象には具体例を添える
- 完璧を求めず、まず書いて後で洗練する。spec は実装を縛るものではなく、導く羅針盤

## Status log

- 2026-11-04: SDG に沿って再構成。`spec/01`, `spec/02` を `docs/spec` へ、`ARCHITECTURE.md` を design 02 に書き直し、`MIDI_DEVICES.md` を guide 02 に整え、
  guide 01（開発の回し方）を新規に起こした。Swift 時代の 12 本、PROJECT_STRUCTURE、Domains、GRAND_DESIGN、Pages の残骸、旧 `spec/README.md` は
  `docs/archive` へ（Deprecated）。`spec/` ディレクトリは空になったので無くなった。旧 `spec/README.md` の体系案（01〜06、99-meta）は踏襲せず、
  番号は spec / design / guide それぞれの連番にした
