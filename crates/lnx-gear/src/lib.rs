//! lnx-gear — Gear ごとの入力正規化・表示投影・設定変換（純粋計算、I/O なし）
//!
//! 接続方式や通信規格（MIDI 1.0 / UMP / SysEx / USB Serial 等）の複雑さを裏に隠し、
//! アプリからは「どのアプリがどの Gear を使うか」として一貫して扱うための純粋層（`data` + `calculations`）。
//! I/O（ポート接続・polling・送出）は含まない — 接続の管理は `lnx-server` の仕事。
//!
//! - [`gear_profile`] — 出力方向: アプリ state → Gear byte 列（LED / 丸液晶 / モーター等の投影）
//! - [`gear_input`] — 入力方向: Gear raw byte → 論理 [`gear_input::ControlEvent`]
//! - [`roto_palette`] — ROTO-CONTROL の色パレット量子化
//! - [`roto_serial`] — ROTO-CONTROL の USB Serial API フレーミング・setup 変換
//! - [`keystage`] — KORG Keystage の接続モード解除フレーム

pub mod gear_input;
pub mod gear_profile;
pub mod keystage;
pub mod roto_palette;
pub mod roto_serial;

pub use gear_input::{ControlEvent, GearInput};
pub use gear_profile::{GearProfile, ParamSpec, Rgb};
