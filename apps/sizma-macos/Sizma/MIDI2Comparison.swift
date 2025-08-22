//
//  MIDI2Comparison.swift
//  LNXX
//
//  MIDI 1.0 と MIDI 2.0 の比較説明
//

import Foundation

// MARK: - MIDI 1.0 メッセージ構造
struct MIDI1Message {
    // 3バイトメッセージ (Note On/Off など)
    let statusByte: UInt8    // 8ビット: [メッセージタイプ(4bit)][チャンネル(4bit)]
    let dataByte1: UInt8     // 7ビット: ノート番号 (0-127)
    let dataByte2: UInt8     // 7ビット: ベロシティ (0-127)
    
    // 例: Note On, Channel 1, Note 60 (Middle C), Velocity 64
    // [0x90] [0x3C] [0x40]
    static let example = "0x90 0x3C 0x40"  // 3バイト
}

// MARK: - MIDI 2.0 メッセージ構造
struct MIDI2Message {
    // Universal MIDI Packet (UMP) - 32ビット/64ビット/128ビット
    
    // 32ビット (4バイト) メッセージ例: MIDI 1.0 Channel Voice
    struct UMP32bit {
        let messageType: UInt8   // 4ビット: メッセージタイプ
        let group: UInt8         // 4ビット: グループ (0-15)
        let status: UInt8        // 8ビット: ステータス
        let channel: UInt8       // 4ビット: チャンネル (0-15)
        let data1: UInt8         // 8ビット: データ1
        let data2: UInt8         // 8ビット: データ2
        
        // 例: [0x20] [0x90] [0x3C] [0x40]
        static let example = "0x20 0x90 0x3C 0x40"  // 4バイト
    }
    
    // 64ビット (8バイト) メッセージ例: MIDI 2.0 Channel Voice
    struct UMP64bit {
        // Word 1 (32ビット)
        let messageType: UInt8   // 4ビット: メッセージタイプ (0x4)
        let group: UInt8         // 4ビット: グループ
        let status: UInt8        // 4ビット: ステータス
        let channel: UInt8       // 4ビット: チャンネル
        let reserved: UInt8      // 8ビット: 予約
        let noteNumber: UInt8    // 8ビット: ノート番号
        
        // Word 2 (32ビット)
        let velocity: UInt16     // 16ビット: ベロシティ (0-65,535)
        let attribute: UInt16    // 16ビット: アトリビュート
        
        // 例: Note On with 16-bit velocity
        // [0x40 0x90 0x00 0x3C] [0x8000 0x0000]
        static let example = "0x40 0x90 0x00 0x3C 0x80 0x00 0x00 0x00"  // 8バイト
    }
}

// MARK: - MIDI 2.0 の新機能
class MIDI2Features {
    
    // 1. 双方向通信
    func bidirectionalCommunication() {
        /*
        MIDI 1.0: 一方向のみ (送信側 → 受信側)
        MIDI 2.0: 双方向通信可能
        
        - デバイスの能力を問い合わせ
        - プロパティ交換 (Property Exchange)
        - 自動設定ネゴシエーション
        */
    }
    
    // 2. Per-Note Controllers
    func perNoteControl() {
        /*
        MIDI 1.0: チャンネル全体に影響
        MIDI 2.0: 個別のノートごとに制御可能
        
        例: 
        - ノートごとのピッチベンド
        - ノートごとのエクスプレッション
        - ノートごとのティンバー調整
        */
    }
    
    // 3. 拡張されたコントローラー
    func expandedControllers() {
        /*
        MIDI 1.0: 128個のCC (Control Change)
        MIDI 2.0: 
        - 32,768個の登録済みコントローラー
        - 32,768個の割り当て可能コントローラー
        */
    }
    
    // 4. システムメッセージの改善
    func improvedSystemMessages() {
        /*
        - JR (Jitter Reduction) タイムスタンプ
        - より正確なタイミング同期
        - マイクロ秒単位の精度
        */
    }
}

// MARK: - 実際のデータ比較例
class MIDIComparison {
    
    // ピアノの中央C (60) を強く叩いた場合
    func noteOnComparison() {
        print("🎹 Note On 比較:")
        print("\nMIDI 1.0:")
        print("  データ: 0x90 0x3C 0x7F")
        print("  サイズ: 3バイト")
        print("  ベロシティ: 127 (最大)")
        print("  解像度: 7ビット (128段階)")
        
        print("\nMIDI 2.0 (32-bit UMP):")
        print("  データ: 0x20 0x90 0x3C 0x7F")
        print("  サイズ: 4バイト")
        print("  ベロシティ: 127 (MIDI 1.0互換)")
        
        print("\nMIDI 2.0 (64-bit UMP):")
        print("  データ: 0x40 0x90 0x00 0x3C 0xFF 0xFF 0x00 0x00")
        print("  サイズ: 8バイト")
        print("  ベロシティ: 65,535 (最大)")
        print("  解像度: 16ビット (65,536段階)")
        print("  追加: アトリビュート情報")
    }
    
    // ピッチベンド比較
    func pitchBendComparison() {
        print("\n🎚 Pitch Bend 比較:")
        print("\nMIDI 1.0:")
        print("  データ: 0xE0 0x00 0x40")
        print("  解像度: 14ビット (16,384段階)")
        
        print("\nMIDI 2.0:")
        print("  データ: 0x40 0xE0 0x00 0x00 0x80 0x00 0x00 0x00")
        print("  解像度: 32ビット (4,294,967,296段階)")
        print("  精度: 約262,000倍向上！")
    }
    
    // エクスプレッション比較
    func expressionComparison() {
        print("\n🎭 Expression 比較:")
        
        print("\nMIDI 1.0 での実装:")
        print("  - Velocity: 打鍵時のみ (7ビット)")
        print("  - Aftertouch: 打鍵後 (7ビット)")
        print("  - CC#11: Expression (7ビット)")
        
        print("\nMIDI 2.0 での実装:")
        print("  - Velocity: 打鍵時 (16ビット)")
        print("  - Per-Note Pitch: ノートごと (32ビット)")
        print("  - Per-Note Timbre: 音色変化 (32ビット)")
        print("  - Per-Note Pressure: 圧力 (32ビット)")
        print("  - Per-Note Expression: 表現 (32ビット)")
    }
}

// MARK: - LPD8での実装例
extension MIDI2Features {
    
    func lpd8WithMIDI2() {
        print("\n🎮 LPD8 が MIDI 2.0 対応した場合:")
        
        print("\n現在 (MIDI 1.0):")
        print("  PAD圧力: 0-127 (128段階)")
        print("  ノブ: 0-127 (128段階)")
        
        print("\nMIDI 2.0 対応後:")
        print("  PAD圧力: 0-65,535 (65,536段階)")
        print("  ノブ: 0-4,294,967,295 (約43億段階)")
        print("  パッドごとの個別ピッチベンド")
        print("  パッドごとのティンバーコントロール")
        print("  双方向通信でLEDフィードバック")
        
        print("\n実用例:")
        print("  - より繊細なドラムロール")
        print("  - 微細なフィルターコントロール")
        print("  - パッドごとの独立したエフェクト")
        print("  - DAWとの完全同期")
    }
}

// MARK: - プロトコルネゴシエーション
class MIDI2Protocol {
    
    func protocolNegotiation() {
        print("\n🤝 MIDI 2.0 プロトコルネゴシエーション:")
        
        print("\n1. Discovery (発見):")
        print("   デバイス: 'MIDI 2.0対応してる？'")
        print("   ホスト: 'Yes! あなたは？'")
        
        print("\n2. Capability Inquiry (能力確認):")
        print("   - サポートするUMPサイズ")
        print("   - グループ数")
        print("   - Per-Note Controllers対応")
        
        print("\n3. Configuration (設定):")
        print("   - 使用するプロトコルバージョン")
        print("   - グループ割り当て")
        print("   - ファンクションブロック設定")
        
        print("\n4. Property Exchange (プロパティ交換):")
        print("   - デバイス名")
        print("   - 製造者情報")
        print("   - パッチ名リスト")
        print("   - コントローラーマッピング")
    }
}

// MARK: - 後方互換性
class MIDI2Compatibility {
    
    func backwardCompatibility() {
        print("\n♻️ MIDI 2.0 の後方互換性:")
        
        print("\nMIDI 1.0デバイスとの接続:")
        print("  - 自動的にMIDI 1.0モードに切り替え")
        print("  - UMP → MIDI 1.0 自動変換")
        print("  - 解像度の自動ダウンスケール")
        
        print("\n変換例:")
        print("  MIDI 2.0: Velocity 32,768 (16-bit)")
        print("  ↓ 自動変換")
        print("  MIDI 1.0: Velocity 64 (7-bit)")
    }
}