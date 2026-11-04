//! 設定ファイル（TOML）— サーバの名前と、知っているサーバの一覧
use std::path::Path;

use anyhow::Context;
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
            .with_context(|| format!("設定 {} を読めない", path.display()))?;
        Self::from_toml(&text).with_context(|| format!("設定 {} が壊れている", path.display()))
    }

    /// `--config` が無いときの設定。`<state_dir>/lnx-server.toml` を読み、無ければ `default_name()` で作って保存する。
    /// 名乗りは iPad が pin を引く鍵なので、証明書と同じく一度決めたら使い続ける。bool は「作った」。
    /// `default_name` は作るときだけ呼ぶ（ホスト名を引くので）
    pub fn load_or_create(
        state_dir: &Path,
        default_name: impl FnOnce() -> String,
    ) -> anyhow::Result<(Self, bool)> {
        let path = state_dir.join(CONFIG_FILE);
        if path.exists() {
            return Ok((Self::load_named(&path)?, false));
        }
        let cfg = Self {
            name: default_name(),
            servers: Vec::new(),
        };
        let text = format!(
            "# lnx-server の設定。最初の起動で作った。\n\
             # name は iPad が pin を引く鍵。変えるとペアリングし直しになる\n{}",
            toml::to_string(&cfg)?
        );
        std::fs::create_dir_all(state_dir)
            .with_context(|| format!("{} を作れない", state_dir.display()))?;
        // 中身ごと一度に、無いときだけ置く: 同じ置き場の一時ファイルに書いてから hard link。
        // 書きかけで落ちても空の設定は残らず、同時に立ち上がったもう一つとも取り合わない（負けたら相手のものを読む）
        let staging = state_dir.join(format!(".{CONFIG_FILE}.{}", std::process::id()));
        std::fs::write(&staging, text)
            .with_context(|| format!("設定 {} を書けない", staging.display()))?;
        let placed = std::fs::hard_link(&staging, &path);
        let _ = std::fs::remove_file(&staging);
        match placed {
            Ok(()) => Ok((cfg, true)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                Ok((Self::load_named(&path)?, false))
            }
            Err(e) => Err(e).with_context(|| format!("設定 {} を置けない", path.display())),
        }
    }

    /// state dir の設定は name が要る。空や書きかけを、黙って既定の名乗り（lnx）として読まない
    fn load_named(path: &Path) -> anyhow::Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("設定 {} を読めない", path.display()))?;
        let table: toml::Table = text
            .parse()
            .with_context(|| format!("設定 {} が壊れている", path.display()))?;
        anyhow::ensure!(
            table.contains_key("name"),
            "設定 {} に name が無い（空なら消すと作り直す。ただし名乗りが変わると iPad はペアリングし直し）",
            path.display()
        );
        Self::from_toml(&text).with_context(|| format!("設定 {} が壊れている", path.display()))
    }
}

/// state dir に置く設定ファイル（`--config` が無いときに読む。無ければ最初の起動で作る）
pub const CONFIG_FILE: &str = "lnx-server.toml";

/// 既定の名乗り: `lnx-<ホスト名>`（小文字、英数字とハイフンだけ。ドメインは落とす）。取れなければ `lnx`。
/// `lnx` 固定だと LAN に 2 台あるとぶつかる（Bonjour が「lnx (2)」に改名し、pin の名前と合わなくなる）
pub fn default_name(host: Option<&str>) -> String {
    let first = host.and_then(|h| h.split('.').next()).unwrap_or("");
    let mut slug = String::new();
    for c in first.chars().map(|c| c.to_ascii_lowercase()) {
        if c.is_ascii_alphanumeric() {
            slug.push(c);
        } else if !slug.ends_with('-') {
            slug.push('-');
        }
    }
    let slug = slug.trim_matches('-');
    if slug.is_empty() {
        return "lnx".into();
    }
    // 名乗りは <name>.local. のホスト名にもなる。DNS のラベルは 63 バイトまで（"lnx-" の 4 を引く。slug は ASCII だけ）
    let slug = slug[..slug.len().min(59)].trim_end_matches('-');
    format!("lnx-{slug}")
}
