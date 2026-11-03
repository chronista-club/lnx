//! lnx-server — LNX サーバ。lnx creare（iPad）が常時つなぐ窓口。
//!
//! 通信は Unison Protocol（club-unison、QUIC）。スキーマは
//! `schemas/lnx.kdl` が正で、バイナリに焼き込んで discovery で配る。
//! 設計は `docs/design/01-lnx-server-link.md`。

pub mod advertise;
pub mod config;
pub mod heartbeat;
pub mod identity;
pub mod registry;
pub mod serve;

/// プロトコル定義（SSOT はファイル。discovery で配るため焼き込む）
pub const LNX_KDL: &str = include_str!("../schemas/lnx.kdl");

/// 既定の待ち受けポート（UDP / QUIC）。旧 lnx-core の 12730 を受け継いだ
pub const DEFAULT_PORT: u16 = 12730;

/// Bonjour のサービス種別
pub const SERVICE_TYPE: &str = "_lnx._udp.local.";
