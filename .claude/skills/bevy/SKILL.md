---
name: bevy
description: Bevy Engine (Rust製ゲームエンジン) を使った開発のためのスキル。ECS、リアルタイムオーディオ/ビジュアル処理、プラグインアーキテクチャに焦点。LNXプロジェクトでのBevy使用時に参照。Use when working with Bevy Engine, ECS patterns, real-time audio/visual processing, or Bevy plugin development.
---

# Bevy Engine スキル

Bevy Engineを効率的に使うための実践的スキルセット。公式ドキュメントへのリンクと、LNXプロジェクトで実際に使用するパターンを中心にまとめています。

## 📝 このスキルの使い方

### いつ使うか

- Bevy Engineのコードを書く時
- ECS（Entity Component System）の実装パターンを知りたい時
- リアルタイムオーディオ/ビジュアル処理を実装する時
- Bevyプラグインを開発する時
- パフォーマンス最適化が必要な時

### 使用例

```
@bevy ECSの基本構造を教えて
@bevy リアルタイムオーディオ処理をBevyで実装したい
@bevy システム間でのイベント通信方法を教えて
@bevy プラグインの作り方を教えて
```

## 🎯 コアコンセプト

### ECS (Entity Component System)

Bevyの中核となるアーキテクチャパターン

- **Entity**: IDを持つゲームオブジェクト
- **Component**: データを保持する構造体
- **System**: ロジックを実行する関数

### アプリケーション構造

```rust
App::new()
    .add_plugins(DefaultPlugins)        // プラグイン
    .add_systems(Startup, setup)        // 起動時システム
    .add_systems(Update, game_logic)    // 更新システム
    .run();
```

## 📚 リファレンス構成

### 基本リファレンス

- **reference/quick_start.md** - インストールと基本構造
- **reference/ecs_essentials.md** - ECS基礎
- **reference/systems.md** - システム設計
- **reference/plugins.md** - プラグイン開発
- **reference/audio.md** - オーディオシステム
- **reference/performance.md** - パフォーマンス最適化

### LNX特化リファレンス

- **reference/lnx_integration.md** - LNXプロジェクトでの統合パターン
- **reference/real_time_optimization.md** - リアルタイム処理最適化（<16ms目標）

### パターン集

- **patterns/common_patterns.md** - よく使うパターン
- **patterns/audio_visual_sync.md** - オーディオ・ビジュアル同期

## 🚀 クイックスタート

### インストール

```toml
[dependencies]
bevy = "0.14"
```

### 最小構成

```rust
use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_systems(Startup, setup)
        .run();
}

fn setup(mut commands: Commands) {
    commands.spawn(Camera2dBundle::default());
}
```

## 🔗 公式リソース

- **公式ドキュメント**: https://bevyengine.org/learn/
- **公式Book**: https://bevyengine.org/learn/book/introduction/
- **Examples**: https://github.com/bevyengine/bevy/tree/main/examples
- **GitHub**: https://github.com/bevyengine/bevy
- **Discord**: https://discord.gg/bevy

## 🎵 LNXプロジェクトでの重点領域

このスキルはLNXプロジェクトでの使用を前提として、以下に焦点を当てています：

1. **リアルタイムオーディオ処理**
   - 低遅延オーディオパイプライン（<16ms目標）
   - オーディオグラフ構築
   - デバイス管理

2. **オーディオ・ビジュアル同期**
   - フレーム同期
   - タイミング制御
   - イベント駆動アーキテクチャ

3. **プラグインアーキテクチャ**
   - モジュラー設計
   - 拡張可能な構造
   - 依存関係管理

4. **パフォーマンス最適化**
   - システムスケジューリング
   - 並列処理
   - メモリ管理

## 📌 設計思想

このスキルは以下の原則で設計されています：

1. **公式ドキュメント優先**: 詳細は公式ドキュメントへのリンクで対応
2. **LNX特化**: LNXプロジェクトでの使用を前提とした情報整理
3. **実践重視**: よく使うパターンとコード例を中心に
4. **リアルタイム性重視**: 低遅延（<16ms）を実現するための知識を優先
5. **段階的な知識蓄積**: 必要に応じてリファレンスを追加していく運用

## 🔄 更新方針

- 必要に応じてリファレンスを追加
- LNXプロジェクトで実際に使用したパターンを随時追加
- バージョン固定せず、安定版（stable）の情報を記載
- APIの詳細は公式ドキュメントへのリンクで対応

## 📝 変更履歴

### v1.0.0 (2025-11-05)

- 初版作成
- 基本的なスキル構造を確立
- LNXプロジェクト向けの重点領域を定義
- リファレンス構成を計画
