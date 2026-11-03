//! 設定ファイル（TOML）— サーバの名前と、知っているサーバの一覧
use std::path::Path;

use serde::{Deserialize, Serialize};

/// LNX が知っているサーバ 1 件（registry の 1 行。wire の形もこれ）
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerEntry {
    /// 一意な名前（例: ladyland.field）
    pub id: String,
    /// 人が読む名前
    pub name: String,
    /// 種別（例: field）。iPad はこれで画面を選ぶ
    pub kind: String,
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct ServerConfig {
    /// 名乗り（Welcome.server_name、Bonjour のインスタンス名）
    pub name: String,
    /// 既知のサーバ。v0 は設定ファイルの固定リスト
    pub servers: Vec<ServerEntry>,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            name: "lnx".into(),
            servers: Vec::new(),
        }
    }
}

impl ServerConfig {
    pub fn from_toml(text: &str) -> Result<Self, toml::de::Error> {
        toml::from_str(text)
    }

    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let text = std::fs::read_to_string(path)
            .map_err(|e| anyhow::anyhow!("設定 {} を読めない: {e}", path.display()))?;
        Ok(Self::from_toml(&text)?)
    }
}
