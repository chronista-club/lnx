---
title: Bevy Engine クイックスタート
version: 1.0.0
date: 2025-11-05
---

# Bevy Engine クイックスタート

## 📦 インストール

### Cargo.tomlへの追加

```toml
[dependencies]
bevy = "0.14"  # 最新の安定版を使用
```

### 動的リンクで開発を高速化（オプション）

```toml
[features]
default = ["bevy/dynamic_linking"]
```

## 🚀 最小構成のアプリケーション

```rust
use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_systems(Startup, setup)
        .add_systems(Update, hello_world)
        .run();
}

fn setup(mut commands: Commands) {
    commands.spawn(Camera2dBundle::default());
}

fn hello_world() {
    println!("Hello, Bevy!");
}
```

## 🎯 基本概念

### ECS (Entity Component System)

- **Entity**: IDを持つゲームオブジェクト
- **Component**: データを保持する構造体
- **System**: ロジックを実行する関数

### App構造

```rust
App::new()
    .add_plugins(DefaultPlugins)        // プラグイン追加
    .add_systems(Startup, setup)        // 起動時システム
    .add_systems(Update, game_logic)    // 更新システム
    .run();                              // アプリ実行
```

## 📝 システムのスケジュール

### 基本的なスケジュール

- **Startup**: アプリ起動時に1度だけ実行
- **Update**: 毎フレーム実行
- **FixedUpdate**: 固定間隔で実行（物理演算など）

```rust
App::new()
    .add_systems(Startup, setup)
    .add_systems(Update, update_system)
    .add_systems(FixedUpdate, physics_system)
    .run();
```

## 🔧 よく使うプラグイン

### DefaultPlugins

Bevyの標準機能セット（ウィンドウ、レンダリング、入力など）

```rust
App::new()
    .add_plugins(DefaultPlugins)
    .run();
```

### MinimalPlugins

最小限のプラグインセット（ヘッドレスアプリなど）

```rust
App::new()
    .add_plugins(MinimalPlugins)
    .run();
```

## 🔗 公式リソース

- **公式Book**: https://bevyengine.org/learn/book/introduction/
- **Examples**: https://github.com/bevyengine/bevy/tree/main/examples
- **チートシート**: https://github.com/jamadazi/bevy-cheatbook

## 💡 LNXプロジェクトでの使用

LNXでは以下の構成を推奨：

```rust
use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(
            WindowPlugin {
                primary_window: Some(Window {
                    title: "LNX - Vision Creative Tool".into(),
                    resolution: (1920., 1080.).into(),
                    ..default()
                }),
                ..default()
            }
        ))
        // LNX固有のプラグイン
        .add_plugins(LnxAudioPlugin)
        .add_plugins(LnxVisualPlugin)
        .run();
}
```

## ⚡ パフォーマンスヒント

1. **開発時は動的リンク**: ビルド時間を大幅短縮
2. **リリース時は最適化**: `--release`フラグを使用
3. **並列システム**: 依存関係のないシステムは自動並列実行される

## 次のステップ

- **reference/ecs_essentials.md** - ECSの詳細を学ぶ
- **reference/app_builder.md** - アプリケーション構造の理解
- **reference/plugins.md** - プラグインの作成方法
