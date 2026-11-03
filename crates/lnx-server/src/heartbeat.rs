//! 心拍 — 常駐の生存証明。1 秒に 1 回、seq と起動からの経過を押し出す
use std::time::Duration;

use serde_json::{Value, json};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Heartbeat {
    pub seq: u64,
    pub uptime: Duration,
}

impl Heartbeat {
    /// wire の形（schemas/lnx.kdl の event "Heartbeat"）
    pub fn to_value(&self) -> Value {
        json!({ "seq": self.seq, "uptime_ms": self.uptime.as_millis() as u64 })
    }
}

/// 心拍の間隔
pub const PERIOD: Duration = Duration::from_secs(1);
