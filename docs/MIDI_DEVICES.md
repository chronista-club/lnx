# MIDI機器仕様書 - LNX

## 使用機器

### 🎹 Korg Keystage 49
**用途**: メインMIDIキーボード、DAWコントロール

#### 基本仕様
- **鍵盤**: 49鍵（4オクターブ）、ベロシティ対応、アフタータッチ非対応
- **接続**: USB-B（USB-MIDI）、MIDI DIN端子（5ピン）
- **電源**: USBバスパワーまたはDCアダプター（9V）
- **MIDI実装**: MIDI 1.0準拠

#### MIDIメッセージ仕様
```rust
// Keystage MIDI実装
const KEYSTAGE_DEVICE_ID: u8 = 0x42;  // Korg ID

// ノートメッセージ
// チャンネル1（デフォルト）: 0x90-0x9F (Note On), 0x80-0x8F (Note Off)
// ノート範囲: C1(24) - C5(72)
// ベロシティ: 1-127（0=Note Off扱い）

// コントロールチェンジ（アサイナブル）
const KEYSTAGE_CC_MAPPINGS: &[(u8, &str)] = &[
    (1,  "Modulation Wheel"),      // モジュレーションホイール
    (7,  "Volume"),                 // ボリュームスライダー
    (10, "Pan"),                    // パンノブ
    (11, "Expression"),             // エクスプレッション
    (64, "Sustain Pedal"),          // サステインペダル端子
    (71, "Filter Resonance"),       // ノブ1（デフォルト）
    (74, "Filter Cutoff"),          // ノブ2（デフォルト）
    (73, "Attack Time"),            // ノブ3（デフォルト）
    (72, "Release Time"),           // ノブ4（デフォルト）
    (75, "Decay Time"),             // ノブ5（デフォルト）
    (76, "Vibrato Rate"),           // ノブ6（デフォルト）
    (77, "Vibrato Depth"),          // ノブ7（デフォルト）
    (78, "Vibrato Delay"),          // ノブ8（デフォルト）
];

// トランスポートコントロール（MMC）
const TRANSPORT_CONTROLS: &[(u8, &str)] = &[
    (0xFA, "Start"),        // 再生開始
    (0xFC, "Stop"),         // 停止
    (0xFB, "Continue"),     // 一時停止/再開
    (0xF2, "Song Position"), // ソングポジション
];
```

#### 特殊機能
- **ページボタン**: CC送信値を8バンク切り替え可能（8ノブ×8ページ=64パラメータ）
- **アルペジエーター**: 内蔵（MIDIクロック同期可能）
- **スケール機能**: メジャー/マイナースケールに限定した演奏モード

#### SysExコマンド
```rust
// Korg Keystage Identity Reply
// F0 7E <device_id> 06 02 42 00 01 <model> <version> F7
const KEYSTAGE_IDENTITY: [u8; 13] = [
    0xF0, 0x7E, 0x00, 0x06, 0x02,
    0x42,              // Korg ID
    0x00, 0x01,        // Sub ID
    0x34, 0x00,        // Keystage Model ID
    0x01, 0x00, 0x00,  // Version
    0xF7
];

// Native Mode切り替え（DAWインテグレーション）
const NATIVE_MODE_ON: [u8; 7] = [
    0xF0, 0x42, 0x40, 0x00, 0x01, 0x35, 0xF7
];
```

---

### 🎛️ Akai LPD8
**用途**: パッドコントローラー、ビートメイキング、パラメータコントロール

#### 基本仕様
- **パッド**: 8個（ベロシティ対応、感圧式）
- **ノブ**: 8個（エンドレスではない、0-127）
- **接続**: USB mini-B（USB-MIDI専用）
- **電源**: USBバスパワーのみ
- **サイズ**: コンパクト（330g）

#### MIDIメッセージ仕様
```rust
// LPD8 MIDI実装
const LPD8_DEFAULT_CHANNEL: u8 = 0x09;  // チャンネル10（ドラム）

// パッドノート割り当て（Program 1 デフォルト）
const PAD_NOTES: [u8; 8] = [
    36,  // Pad 1: C1  (Kick)
    37,  // Pad 2: C#1 (Snare Side)
    38,  // Pad 3: D1  (Snare)
    39,  // Pad 4: D#1 (Clap)
    40,  // Pad 5: E1  (Snare 2)
    41,  // Pad 6: F1  (Low Tom)
    42,  // Pad 7: F#1 (Closed HH)
    43,  // Pad 8: G1  (Low Tom 2)
];

// CC（Control Change）モード時のパッド
const PAD_CC_NUMBERS: [u8; 8] = [
    1, 2, 3, 4, 5, 6, 7, 8  // CC1-8（Program依存）
];

// ノブのCC番号（Program 1 デフォルト）
const KNOB_CC_NUMBERS: [u8; 8] = [
    1,   // K1: Modulation
    2,   // K2: Breath Controller
    3,   // K3: Controller 3
    4,   // K4: Foot Controller
    5,   // K5: Portamento Time
    6,   // K6: Data Entry MSB
    7,   // K7: Channel Volume
    8,   // K8: Balance
];

// プログラムチェンジ対応
// 4つのプリセット（PAD/CC切り替え可能）
const PROGRAMS: [(u8, &str); 4] = [
    (0, "Preset 1 - Drums"),
    (1, "Preset 2 - Melodic"),
    (2, "Preset 3 - User 1"),
    (3, "Preset 4 - User 2"),
];
```

#### パッドモード
```rust
pub enum PadMode {
    Note,        // ノート送信（ドラムパッド）
    CC,          // CCトグル（0/127切り替え）
    ProgramChange, // プログラムチェンジ送信
}

// ベロシティカーブ設定
pub enum VelocityCurve {
    Linear,      // リニア応答
    Exponential, // 指数カーブ（軽いタッチで大きな変化）
    Logarithmic, // 対数カーブ（強いタッチが必要）
    Fixed(u8),   // 固定ベロシティ（1-127）
}
```

#### エディタソフトウェア設定
LPD8 Editorで以下の設定が可能：
- パッドのノート番号/CC番号
- ノブのCC番号/範囲
- MIDIチャンネル（1-16）
- パッドのモード切り替え
- ベロシティカーブ

---

## lnx-engineでの実装例

```rust
use midir::{MidiInput, MidiOutput};

pub struct MidiDeviceManager {
    keystage: Option<MidiInputPort>,
    lpd8: Option<MidiInputPort>,
}

impl MidiDeviceManager {
    pub fn auto_detect() -> Result<Self, Box<dyn Error>> {
        let input = MidiInput::new("lnx-midi")?;
        let mut manager = Self {
            keystage: None,
            lpd8: None,
        };

        // ポート名で自動検出
        for port in input.ports() {
            let name = input.port_name(&port)?;

            if name.contains("Keystage") || name.contains("KEYSTAGE") {
                println!("✅ Korg Keystage detected: {}", name);
                manager.keystage = Some(port);
            } else if name.contains("LPD8") {
                println!("✅ Akai LPD8 detected: {}", name);
                manager.lpd8 = Some(port);
            }
        }

        Ok(manager)
    }

    pub fn setup_keystage_callback<F>(&self, mut callback: F)
    where F: FnMut(u8, &[u8]) + Send + 'static
    {
        // Keystage入力処理
        let _conn = self.input.connect(
            &self.keystage.unwrap(),
            "lnx-keystage",
            move |stamp, message, _| {
                match message[0] & 0xF0 {
                    0x90 | 0x80 => {  // Note On/Off
                        println!("🎹 Note: {} Vel: {}", message[1], message[2]);
                    },
                    0xB0 => {  // Control Change
                        println!("🎛️ CC{}: {}", message[1], message[2]);
                    },
                    _ => {}
                }
                callback(stamp, message);
            },
            (),
        );
    }

    pub fn setup_lpd8_callback<F>(&self, mut callback: F)
    where F: FnMut(u8, &[u8]) + Send + 'static
    {
        // LPD8パッド処理
        let _conn = self.input.connect(
            &self.lpd8.unwrap(),
            "lnx-lpd8",
            move |stamp, message, _| {
                if message[0] == 0x99 {  // Ch10 Note On
                    let pad_index = PAD_NOTES.iter()
                        .position(|&n| n == message[1])
                        .unwrap_or(0);
                    println!("🥁 Pad {}: Velocity {}", pad_index + 1, message[2]);
                }
                callback(stamp, message);
            },
            (),
        );
    }
}
```

## 推奨設定

### Keystage
1. **MIDIチャンネル**: 1（メロディ）
2. **ノブアサイン**: lnx-engine用カスタムCC
3. **ベロシティカーブ**: Normal
4. **ペダル**: サステイン接続推奨

### LPD8
1. **MIDIチャンネル**: 10（ドラム）
2. **パッドモード**: Note（ビート作成時）
3. **ノブ**: エフェクトパラメータにマップ
4. **プログラム**: 用途別に4つ設定

## トラブルシューティング

### 認識されない場合
```bash
# macOS: MIDI Studio確認
open /Applications/Utilities/Audio\ MIDI\ Setup.app

# 権限確認
ls -la /dev/cu.* | grep -i midi
```

### レイテンシー対策
- バッファサイズ: 64-128サンプル推奨
- USBハブを避けて直接接続
- 他のUSB機器との干渉を避ける

### ドライバー
- **Keystage**: ドライバー不要（Class Compliant）
- **LPD8**: ドライバー不要（Class Compliant）