## Language Guideline

日本語をメイン言語とします。
文書や、コメント、メッセージ等は日本語でお願いします。

# sizma (静馬) C4 アーキテクチャ図

## 概要
このドキュメントは、sizma (静馬)プロジェクトのシステムアーキテクチャをC4モデルを使用して視覚化したものです。

## C4 Level 1: システムコンテキスト図

```mermaid
C4Context
    title sizma システムコンテキスト図
    
    Person(musician, "ミュージシャン", "リアルタイム音声/視覚パフォーマンスを行うアーティスト")
    Person(soundArtist, "サウンドアーティスト", "音声処理と視覚効果を組み合わせた作品を作成するアーティスト")
    Person(vj, "VJ", "視覚的なパフォーマンスを行うアーティスト")
    
    System(lnxx, "sizma", "リアルタイム音声/視覚パフォーマンス用macOSアプリケーション")
    
    System_Ext(audioDevice, "オーディオデバイス", "USBオーディオインターフェース、MIDIコントローラー")
    System_Ext(display, "ディスプレイ", "プロジェクター、LEDディスプレイ、VR/ARデバイス")
    System_Ext(storage, "ストレージ", "ローカルファイルシステム、クラウドストレージ")
    
    Rel(musician, lnxx, "音声/視覚パフォーマンスを実行")
    Rel(soundArtist, lnxx, "リアルタイム音声処理と視覚効果を操作")
    Rel(vj, lnxx, "視覚的なパフォーマンスを制御")
    
    Rel(lnxx, audioDevice, "低遅延音声入出力")
    Rel(lnxx, display, "高品質視覚出力")
    Rel(lnxx, storage, "プロジェクトファイルとオーディオファイルの読み書き")
```

## C4 Level 2: コンテナ図

```mermaid
C4Container
    title sizma コンテナ図
    
    Person(user, "ユーザー", "ミュージシャン、サウンドアーティスト、VJ")
    
    Container_Boundary(lnxx, "sizma") {
        Container(ui, "SwiftUI UI", "SwiftUI", "ユーザーインターフェース、リアクティブUI更新")
        Container(audioEngine, "オーディオエンジン", "Core Audio", "リアルタイム音声処理、低遅延音声入出力")
        Container(visualEngine, "視覚エンジン", "Metal", "リアルタイム視覚効果、GPU処理")
        Container(syncEngine, "同期エンジン", "Swift", "音声/視覚同期、ネットワーク同期")
        Container(projectManager, "プロジェクトマネージャー", "Swift", "プロジェクトファイル管理、データモデル")
    }
    
    ContainerDb(fileSystem, "ファイルシステム", "macOS File System", "プロジェクトファイル、オーディオファイル、設定")
    ContainerDb(audioFiles, "オーディオファイル", "WAV/AIFF", "304MBのテストオーディオファイル")
    
    Rel(user, ui, "操作")
    Rel(ui, audioEngine, "音声制御")
    Rel(ui, visualEngine, "視覚効果制御")
    Rel(ui, syncEngine, "同期設定")
    Rel(ui, projectManager, "プロジェクト操作")
    
    Rel(audioEngine, fileSystem, "オーディオファイル読み込み")
    Rel(visualEngine, fileSystem, "視覚アセット読み込み")
    Rel(projectManager, fileSystem, "プロジェクトファイル保存/読み込み")
    Rel(syncEngine, audioEngine, "音声同期")
    Rel(syncEngine, visualEngine, "視覚同期")
```

## C4 Level 3: コンポーネント図

```mermaid
C4Component
    title sizma オーディオエンジンコンポーネント図
    
    Container_Boundary(audioEngine, "オーディオエンジン") {
        Component(audioSession, "AudioSession", "Core Audio", "オーディオセッション管理、デバイス列挙")
        Component(audioProcessor, "AudioProcessor", "Core Audio", "リアルタイム音声処理、バッファ操作")
        Component(audioPlayer, "AudioPlayer", "AVFoundation", "オーディオファイル再生、ストリーミング")
        Component(latencyMonitor, "LatencyMonitor", "Swift", "遅延測定、パフォーマンス監視")
        Component(midiController, "MIDIController", "Core MIDI", "MIDIデバイス制御、イベント処理")
    }
    
    Container(ui, "SwiftUI UI")
    ContainerDb(audioFiles, "オーディオファイル")
    System_Ext(audioDevice, "オーディオデバイス")
    
    Rel(ui, audioSession, "デバイス選択")
    Rel(ui, audioPlayer, "再生制御")
    Rel(ui, midiController, "MIDI設定")
    
    Rel(audioSession, audioDevice, "デバイス接続")
    Rel(audioPlayer, audioFiles, "ファイル読み込み")
    Rel(audioProcessor, audioSession, "音声処理")
    Rel(latencyMonitor, audioProcessor, "遅延測定")
    Rel(midiController, audioProcessor, "MIDIイベント")
```

## C4 Level 4: コード図

```mermaid
C4Code
    title sizma オーディオ処理コード図
    
    Component_Boundary(audioProcessor, "AudioProcessor") {
        Class(AudioBuffer, "AudioBuffer", "音声バッファ管理")
        Class(AudioFormat, "AudioFormat", "音声フォーマット変換")
        Class(AudioEffect, "AudioEffect", "音声エフェクト処理")
        Class(AudioScheduler, "AudioScheduler", "音声スケジューリング")
    }
    
    Component_Boundary(audioSession, "AudioSession") {
        Class(AudioDevice, "AudioDevice", "オーディオデバイス管理")
        Class(AudioSession, "AudioSession", "セッション管理")
        Class(AudioRoute, "AudioRoute", "音声ルーティング")
    }
    
    Rel(AudioSession, AudioDevice, "デバイス管理")
    Rel(AudioProcessor, AudioBuffer, "バッファ処理")
    Rel(AudioProcessor, AudioFormat, "フォーマット変換")
    Rel(AudioProcessor, AudioEffect, "エフェクト適用")
    Rel(AudioScheduler, AudioProcessor, "スケジューリング")
```

## 技術仕様

### パフォーマンス要件
- **音声遅延**: 現在の目標 <20ms、将来の目標 <5ms
- **GUI応答性**: 60fps以上
- **メモリ管理**: 大容量オーディオファイル（304MB合計）の効率的な処理

### 開発環境
- **プラットフォーム**: macOS 15.5+ (Sequoia) 必須
- **IDE**: Xcode 16.0+ 必須
- **言語**: Swift 6.0+
- **フレームワーク**: SwiftUI、Core Audio、AVFoundation、Metal Performance Shaders統合予定

### アーキテクチャガイドライン
- **モジュラー設計**: 独立したAudio/Visual/Syncモジュール
- **ECSライクパターン**: リアルタイム処理用のEntity-Componentシステム
- **プロトコル指向**: 柔軟でテスト可能な設計のためのSwiftプロトコル
- **Core Audio統合**: 最小遅延での低レベル音声処理
```

新しいファイル `CLAUDE_C4.md` を作成しました。このファイルには、sizmaプロジェクトのC4モデルアーキテクチャ図が含まれています。

ファイルの場所は以下です：
```
/Users/mito/repos/lnx-experience/CLAUDE_C4.md
```

このファイルを確認していただけますでしょうか？
- コメント等メイン言語は日本語でお願いします。