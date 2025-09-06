use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use std::time::Instant;
use atomic_float::AtomicF32;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use crate::audio_file::SharedAudioFilePlayer;

/// ビートマシンのパッド定義
#[derive(Debug)]
pub struct DrumPad {
    pub id: usize,
    pub name: String,
    pub sample_player: Option<SharedAudioFilePlayer>,
    pub volume: AtomicF32,
    pub mute: AtomicBool,
    pub solo: AtomicBool,
    pub velocity_sensitivity: AtomicF32,
}

impl DrumPad {
    pub fn new(id: usize, name: &str) -> Self {
        Self {
            id,
            name: name.to_string(),
            sample_player: None,
            volume: AtomicF32::new(1.0),
            mute: AtomicBool::new(false),
            solo: AtomicBool::new(false),
            velocity_sensitivity: AtomicF32::new(1.0),
        }
    }

    pub fn load_sample(&mut self, sample_player: SharedAudioFilePlayer) {
        self.sample_player = Some(sample_player);
    }

    pub fn trigger(&self, velocity: f32) {
        if let Some(ref player) = self.sample_player {
            if let Ok(mut player_guard) = player.try_lock() {
                let effective_velocity = velocity * self.velocity_sensitivity.load(Ordering::Relaxed);
                player_guard.set_gain(effective_velocity * self.volume.load(Ordering::Relaxed));
                player_guard.play();
            }
        }
    }

    pub fn set_volume(&self, volume: f32) {
        self.volume.store(volume.clamp(0.0, 2.0), Ordering::Relaxed);
    }

    pub fn set_mute(&self, mute: bool) {
        self.mute.store(mute, Ordering::Relaxed);
    }

    pub fn set_solo(&self, solo: bool) {
        self.solo.store(solo, Ordering::Relaxed);
    }

    pub fn is_muted(&self) -> bool {
        self.mute.load(Ordering::Relaxed)
    }

    pub fn is_solo(&self) -> bool {
        self.solo.load(Ordering::Relaxed)
    }
}

/// シーケンサーのステップ情報
#[derive(Debug, Clone)]
pub struct SequencerStep {
    pub active: bool,
    pub velocity: f32,
    pub pad_id: usize,
}

impl SequencerStep {
    pub fn new(pad_id: usize) -> Self {
        Self {
            active: false,
            velocity: 1.0,
            pad_id,
        }
    }

    pub fn activate(&mut self, velocity: f32) {
        self.active = true;
        self.velocity = velocity.clamp(0.0, 1.0);
    }

    pub fn deactivate(&mut self) {
        self.active = false;
    }
}

/// シーケンサーパターン
#[derive(Debug, Clone)]
pub struct SequencerPattern {
    pub id: usize,
    pub name: String,
    pub steps: Vec<Vec<SequencerStep>>, // [step][pad]
    pub length: usize,
}

impl SequencerPattern {
    pub fn new(id: usize, name: &str, num_steps: usize, num_pads: usize) -> Self {
        let mut steps = Vec::new();
        for _step in 0..num_steps {
            let mut step_pads = Vec::new();
            for pad in 0..num_pads {
                step_pads.push(SequencerStep::new(pad));
            }
            steps.push(step_pads);
        }

        Self {
            id,
            name: name.to_string(),
            steps,
            length: num_steps,
        }
    }

    pub fn set_step(&mut self, step: usize, pad: usize, active: bool, velocity: f32) {
        if step < self.steps.len() && pad < self.steps[step].len() {
            if active {
                self.steps[step][pad].activate(velocity);
            } else {
                self.steps[step][pad].deactivate();
            }
        }
    }

    pub fn get_step(&self, step: usize, pad: usize) -> Option<&SequencerStep> {
        self.steps.get(step)?.get(pad)
    }

    pub fn clear(&mut self) {
        for step in &mut self.steps {
            for pad_step in step {
                pad_step.deactivate();
            }
        }
    }
}

/// BPM管理とタイミング制御
#[derive(Debug)]
pub struct TempoController {
    bpm: AtomicF32,
    last_step_time: Mutex<Instant>,
    step_duration: AtomicF32, // ステップ間隔（秒）
}

impl TempoController {
    pub fn new(bpm: f32) -> Self {
        let step_duration = 60.0 / (bpm * 4.0); // 16分音符基準
        Self {
            bpm: AtomicF32::new(bpm),
            last_step_time: Mutex::new(Instant::now()),
            step_duration: AtomicF32::new(step_duration),
        }
    }

    pub fn set_bpm(&self, bpm: f32) {
        let clamped_bpm = bpm.clamp(60.0, 200.0);
        self.bpm.store(clamped_bpm, Ordering::Relaxed);
        
        let step_duration = 60.0 / (clamped_bpm * 4.0);
        self.step_duration.store(step_duration, Ordering::Relaxed);
    }

    pub fn get_bpm(&self) -> f32 {
        self.bpm.load(Ordering::Relaxed)
    }

    pub fn should_advance_step(&self) -> bool {
        if let Ok(last_time) = self.last_step_time.try_lock() {
            let now = Instant::now();
            let elapsed = now.duration_since(*last_time).as_secs_f32();
            elapsed >= self.step_duration.load(Ordering::Relaxed)
        } else {
            false
        }
    }

    pub fn advance_step(&self) {
        if let Ok(mut last_time) = self.last_step_time.try_lock() {
            *last_time = Instant::now();
        }
    }
}

/// メインのビートマシン構造体
pub struct BeatMachine {
    /// 16個のドラムパッド（4x4グリッド）
    pub pads: Vec<DrumPad>,
    
    /// 現在のパターン
    pub current_pattern: Arc<Mutex<SequencerPattern>>,
    
    /// 保存されたパターン（最大8パターン）
    pub patterns: HashMap<usize, Arc<Mutex<SequencerPattern>>>,
    
    /// テンポコントローラー
    pub tempo_controller: TempoController,
    
    /// シーケンサーの状態
    pub is_playing: AtomicBool,
    pub current_step: AtomicUsize,
    
    /// パフォーマンス制御
    pub master_volume: AtomicF32,
    pub swing: AtomicF32, // スイング量（0.0-1.0）
}

impl BeatMachine {
    pub fn new() -> Self {
        // 16個のドラムパッド作成
        let mut pads = Vec::new();
        let pad_names = [
            "Kick", "Snare", "Hi-hat", "Open Hat",
            "Crash", "Ride", "Tom 1", "Tom 2",
            "Clap", "Perc 1", "Perc 2", "Perc 3",
            "FX 1", "FX 2", "FX 3", "FX 4"
        ];

        for (i, name) in pad_names.iter().enumerate() {
            pads.push(DrumPad::new(i, name));
        }

        // デフォルトパターン作成
        let default_pattern = Arc::new(Mutex::new(
            SequencerPattern::new(0, "Pattern 1", 16, 16)
        ));

        // パターンコレクション初期化
        let mut patterns = HashMap::new();
        patterns.insert(0, default_pattern.clone());

        Self {
            pads,
            current_pattern: default_pattern,
            patterns,
            tempo_controller: TempoController::new(120.0),
            is_playing: AtomicBool::new(false),
            current_step: AtomicUsize::new(0),
            master_volume: AtomicF32::new(1.0),
            swing: AtomicF32::new(0.0),
        }
    }

    /// パッドの手動トリガー
    pub fn trigger_pad(&self, pad_id: usize, velocity: f32) {
        if pad_id < self.pads.len() {
            self.pads[pad_id].trigger(velocity);
        }
    }

    /// シーケンサーの再生開始
    pub fn play(&self) {
        self.is_playing.store(true, Ordering::Relaxed);
        self.current_step.store(0, Ordering::Relaxed);
    }

    /// シーケンサーの停止
    pub fn stop(&self) {
        self.is_playing.store(false, Ordering::Relaxed);
    }

    /// BPM設定
    pub fn set_bpm(&self, bpm: f32) {
        self.tempo_controller.set_bpm(bpm);
    }

    /// シーケンサー処理（オーディオコールバックから呼ばれる）
    pub fn process_sequencer(&self) {
        if !self.is_playing.load(Ordering::Relaxed) {
            return;
        }

        if self.tempo_controller.should_advance_step() {
            self.tempo_controller.advance_step();
            
            let current_step = self.current_step.load(Ordering::Relaxed);
            
            // 現在のパターンから該当ステップのイベントを取得
            if let Ok(pattern) = self.current_pattern.try_lock() {
                if let Some(step_data) = pattern.steps.get(current_step) {
                    // 各パッドの状態をチェックしてトリガー
                    for (pad_id, step) in step_data.iter().enumerate() {
                        if step.active && pad_id < self.pads.len() {
                            // スイング適用（奇数ステップでのタイミング調整）
                            let swing_amount = self.swing.load(Ordering::Relaxed);
                            if current_step % 2 == 1 && swing_amount > 0.0 {
                                // スイング実装は簡略化（実際にはタイミング遅延が必要）
                                let adjusted_velocity = step.velocity * (1.0 + swing_amount * 0.1);
                                self.pads[pad_id].trigger(adjusted_velocity);
                            } else {
                                self.pads[pad_id].trigger(step.velocity);
                            }
                        }
                    }
                }
            }

            // 次のステップに進む
            let next_step = (current_step + 1) % 16;
            self.current_step.store(next_step, Ordering::Relaxed);
        }
    }

    /// パターンのステップを設定
    pub fn set_step(&self, step: usize, pad: usize, active: bool, velocity: f32) {
        if let Ok(mut pattern) = self.current_pattern.try_lock() {
            pattern.set_step(step, pad, active, velocity);
        }
    }

    /// パターン切り替え
    pub fn switch_pattern(&mut self, pattern_id: usize) {
        if let Some(pattern) = self.patterns.get(&pattern_id) {
            self.current_pattern = pattern.clone();
            self.current_step.store(0, Ordering::Relaxed);
        }
    }

    /// 新しいパターン作成
    pub fn create_pattern(&mut self, pattern_id: usize, name: &str) {
        let new_pattern = Arc::new(Mutex::new(
            SequencerPattern::new(pattern_id, name, 16, 16)
        ));
        self.patterns.insert(pattern_id, new_pattern);
    }

    /// マスターボリューム設定
    pub fn set_master_volume(&self, volume: f32) {
        self.master_volume.store(volume.clamp(0.0, 2.0), Ordering::Relaxed);
    }

    /// スイング設定
    pub fn set_swing(&self, swing: f32) {
        self.swing.store(swing.clamp(0.0, 1.0), Ordering::Relaxed);
    }

    /// 現在の再生状態を取得
    pub fn is_playing(&self) -> bool {
        self.is_playing.load(Ordering::Relaxed)
    }

    /// 現在のステップを取得
    pub fn get_current_step(&self) -> usize {
        self.current_step.load(Ordering::Relaxed)
    }

    /// BPMを取得
    pub fn get_bpm(&self) -> f32 {
        self.tempo_controller.get_bpm()
    }
    
    /// オーディオ処理（サンプル再生音を出力バッファにミックス）
    pub fn process_audio(&self, output: &mut [f32], channels: usize) {
        let buffer_size = output.len() / channels;
        let master_vol = self.master_volume.load(Ordering::Relaxed);
        
        
        // 各パッドからの音声をミックス
        for (pad_idx, pad) in self.pads.iter().enumerate() {
            if let Some(ref sample_player) = pad.sample_player {
                if let Ok(mut player) = sample_player.try_lock() {
                    if player.is_playing() {
                        // まず、サンプルファイルのチャンネル数を確認
                        let file_channels = player.get_info().channels;
                        
                        // AudioFilePlayer用のチャンネル配列を作成（サンプルファイルのチャンネル数に合わせる）
                        let mut temp_channels = vec![vec![0.0f32; buffer_size]; file_channels];
                        
                        // サンプルを処理
                        let samples_processed = player.process_audio(&mut temp_channels);
                        
                        // サンプルが処理されなかった場合はスキップ
                        if samples_processed == 0 {
                            continue;
                        }
                        
                        // パッドのボリューム・ミュート・ソロ設定を適用
                        let pad_volume = pad.volume.load(Ordering::Relaxed);
                        let is_muted = pad.is_muted();
                        let is_solo = pad.is_solo();
                        
                        // ソロの確認（他にソロがあるかチェック）
                        let has_solo = self.pads.iter().any(|p| p.is_solo());
                        let should_play = !is_muted && (!has_solo || is_solo);
                        
                        if should_play {
                            // チャンネル配列からインターリーブされた出力バッファに変換
                            for sample_idx in 0..buffer_size {
                                for ch in 0..channels {
                                    let output_idx = sample_idx * channels + ch;
                                    if output_idx < output.len() {
                                        let sample = if file_channels == 1 {
                                            // モノラルサンプルの場合、チャンネル0のデータを全ての出力チャンネルに出力
                                            if sample_idx < temp_channels[0].len() {
                                                temp_channels[0][sample_idx]
                                            } else {
                                                0.0
                                            }
                                        } else if ch < temp_channels.len() && sample_idx < temp_channels[ch].len() {
                                            // ステレオ以上の場合、対応するチャンネルから取得
                                            temp_channels[ch][sample_idx]
                                        } else {
                                            // 対応するチャンネルがない場合は無音
                                            0.0
                                        };
                                        output[output_idx] += sample * pad_volume * master_vol;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

impl Default for BeatMachine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_drum_pad_creation() {
        let pad = DrumPad::new(0, "Test Pad");
        assert_eq!(pad.id, 0);
        assert_eq!(pad.name, "Test Pad");
        assert!(!pad.is_muted());
        assert!(!pad.is_solo());
    }

    #[test]
    fn test_sequencer_pattern() {
        let mut pattern = SequencerPattern::new(0, "Test Pattern", 16, 4);
        
        // ステップ0のパッド0をアクティブに
        pattern.set_step(0, 0, true, 0.8);
        
        let step = pattern.get_step(0, 0).unwrap();
        assert!(step.active);
        assert!((step.velocity - 0.8).abs() < f32::EPSILON);
    }

    #[test]
    fn test_tempo_controller() {
        let tempo = TempoController::new(120.0);
        assert!((tempo.get_bpm() - 120.0).abs() < f32::EPSILON);
        
        tempo.set_bpm(140.0);
        assert!((tempo.get_bpm() - 140.0).abs() < f32::EPSILON);
        
        // BPM範囲制限テスト
        tempo.set_bpm(300.0);
        assert!((tempo.get_bpm() - 200.0).abs() < f32::EPSILON);
        
        tempo.set_bpm(30.0);
        assert!((tempo.get_bpm() - 60.0).abs() < f32::EPSILON);
    }

    #[test]
    fn test_beatmachine_basic() {
        let beatmachine = BeatMachine::new();
        assert_eq!(beatmachine.pads.len(), 16);
        assert!(!beatmachine.is_playing());
        assert_eq!(beatmachine.get_current_step(), 0);
        assert!((beatmachine.get_bpm() - 120.0).abs() < f32::EPSILON);
    }

    #[test]
    fn test_beatmachine_playback_control() {
        let beatmachine = BeatMachine::new();
        
        beatmachine.play();
        assert!(beatmachine.is_playing());
        
        beatmachine.stop();
        assert!(!beatmachine.is_playing());
    }

    #[test]
    fn test_pattern_step_setting() {
        let beatmachine = BeatMachine::new();
        
        // ステップ0のパッド0をアクティブに
        beatmachine.set_step(0, 0, true, 0.7);
        
        if let Ok(pattern) = beatmachine.current_pattern.try_lock() {
            let step = pattern.get_step(0, 0).unwrap();
            assert!(step.active);
            assert!((step.velocity - 0.7).abs() < f32::EPSILON);
        }
    }
}