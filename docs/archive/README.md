# archive — 古い文書

消さずに残す。どれも Status は **Deprecated** で、各ファイルの冒頭に「何に置き換わったか / なぜ残しているか」を 1〜2 行で書いてある。
新しい文書（spec / design / guide）からここを参照することはあるが、ここに追記はしない。

| ファイル | 元の場所 | 時期 | 何だったか | 置き換え先 |
|---|---|---|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | `docs/ARCHITECTURE.md` | 2025-09 | Unison エコシステム前提のアーキテクチャ構想。分散処理・自動スケーリング・Prometheus・Docker まで含む | [design 02](../design/02-architecture.md) |
| [SPEC_README.md](SPEC_README.md) | `spec/README.md` | 2025-11 | spec ディレクトリの思想、体系案（01〜06、99-meta）、frontmatter 形式、commit 規約 | [docs/README.md](../README.md)、[spec 01](../spec/01-core-concept.md) |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | `docs/PROJECT_STRUCTURE.md` | 2025-08 | Swift / SwiftUI（LNXX、macOS アプリ）時代の構成文書 | [design 02](../design/02-architecture.md)、[guide 01](../guide/01-development.md) |
| [TECHNICAL_ARCHITECTURE.md](TECHNICAL_ARCHITECTURE.md) | `docs/TECHNICAL_ARCHITECTURE.md` | 2025-08 | 同時代の技術アーキテクチャ | design 02 |
| [MODULAR_ARCHITECTURE_SPEC.md](MODULAR_ARCHITECTURE_SPEC.md) | `docs/MODULAR_ARCHITECTURE_SPEC.md` | 2025-08 | 同時代のモジュラー設計（Core Audio / Metal） | design 02 |
| [phase2/ARCHITECTURE_REVIEW_SUMMARY.md](phase2/ARCHITECTURE_REVIEW_SUMMARY.md) | `docs/phase2/` | 2025-08 | Phase 2 設計のレビュー | design 02 |
| [phase2/ECS_ARCHITECTURE.md](phase2/ECS_ARCHITECTURE.md) | `docs/phase2/` | 2025-08 | ECS 設計 | design 02 |
| [phase2/MODULAR_DESIGN_SPECIFICATION.md](phase2/MODULAR_DESIGN_SPECIFICATION.md) | `docs/phase2/` | 2025-08 | 6 モジュール（Audio / Visual / Sync / UI / Models / Utils）の設計 | design 02 |
| [phase2/SYSTEM_ARCHITECTURE_DIAGRAMS.md](phase2/SYSTEM_ARCHITECTURE_DIAGRAMS.md) | `docs/phase2/` | 2025-08 | システム図 | design 02 |
| [phase2/TECH_STACK_INTEGRATION.md](phase2/TECH_STACK_INTEGRATION.md) | `docs/phase2/` | 2025-08 | SwiftUI + Core Audio + Metal の統合設計 | design 02 |
| [phase3/AUDIO_OPTIMIZATION_GUIDE.md](phase3/AUDIO_OPTIMIZATION_GUIDE.md) | `docs/phase3/` | 2025-08 | Core Audio の最適化ガイド | 無し（必要になったら guide に） |
| [phase3/DEVELOPMENT_GUIDELINES_SUMMARY.md](phase3/DEVELOPMENT_GUIDELINES_SUMMARY.md) | `docs/phase3/` | 2025-08 | Phase 3 ガイドライン 4 本のまとめ | guide 01 |
| [phase3/PERFORMANCE_REQUIREMENTS.md](phase3/PERFORMANCE_REQUIREMENTS.md) | `docs/phase3/` | 2025-08 | 性能要件と測定システム | 目標値は spec 01 / spec 02。実測の記録は無い |
| [phase3/SWIFTUI_BEST_PRACTICES.md](phase3/SWIFTUI_BEST_PRACTICES.md) | `docs/phase3/` | 2025-08 | SwiftUI（MVVM / Combine）のベストプラクティス | 無し（必要になったら guide に） |
| [phase3/TESTING_STRATEGY.md](phase3/TESTING_STRATEGY.md) | `docs/phase3/` | 2025-08 | テスト戦略 | [design 01](../design/01-lnx-server-link.md)（テストの三層） |
| [GRAND_DESIGN.md](GRAND_DESIGN.md) | `docs/GRAND_DESIGN.md` | 2025-09 | 「My Projects」の mindmap 1 枚 | 無し |
| [Domains.md](Domains.md) | `docs/Domains.md` | 2017-06 | AudioKit / Cocoa 時代のドメイン分割メモ | design 02 |
| [pages/_config.yml](pages/_config.yml)、[pages/index.html](pages/index.html)、[pages/index2.md](pages/index2.md) | `docs/` 直下 | 2017-06 | GitHub Pages（jekyll-theme-cayman）の残骸 | [docs/README.md](../README.md) |

`_config.yml` と `index.html` を `docs/` 直下から外したので、GitHub Pages が `docs/` を公開していた場合は `docs/README.md` が index になる（Pages の設定は未確認）。

## Status log

- 2026-11-04: docs を SDG（spec / design / guide）に再構成したときに作成。上の 20 ファイルを `git mv` で移し、冒頭に Deprecated の見出しを足した。
  `PROJECT_STRUCTURE.md` の関連文書リンクだけ、移動後も辿れるように相対パスへ直した
