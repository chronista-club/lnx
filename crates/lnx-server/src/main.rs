//! lnx-server — 起動して待ち受ける（常駐プロセスの本体）
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Result;
use clap::Parser;
use tracing::{info, warn};

use lnx_server::advertise::Advertiser;
use lnx_server::config::ServerConfig;
use lnx_server::identity::{self, ServerIdentity};
use lnx_server::{DEFAULT_PORT, serve};

#[derive(Parser, Debug)]
#[command(
    name = "lnx-server",
    about = "LNX サーバ — lnx creare が常時つなぐ窓口（Unison / QUIC）"
)]
struct Cli {
    /// 待ち受けアドレス（UDP / QUIC）
    #[arg(long, env = "LNX_SERVER_ADDR", default_value_t = format!("[::]:{DEFAULT_PORT}"))]
    addr: String,
    /// 設定ファイル（TOML）。無ければ既定（名前 lnx、既知サーバ無し）
    #[arg(long, env = "LNX_SERVER_CONFIG")]
    config: Option<PathBuf>,
    /// 名乗りを上書き
    #[arg(long)]
    name: Option<String>,
    /// Bonjour で名乗らない
    #[arg(long)]
    no_mdns: bool,
    /// 証明書と鍵の置き場（既定は ~/Library/Application Support/club.chronista.lnx-server）。
    /// 消すと次の起動で作り直し、アプリはペアリングし直しになる
    #[arg(long, env = "LNX_SERVER_STATE")]
    state_dir: Option<PathBuf>,
    /// 起動時にペアリング用の QR を出さない（URL の一行は出す）
    #[arg(long)]
    no_qr: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with_target(false)
        .init();

    let cli = Cli::parse();
    let mut cfg = match &cli.config {
        Some(path) => ServerConfig::load(path)?,
        None => ServerConfig::default(),
    };
    if let Some(name) = cli.name {
        cfg.name = name;
    }
    info!(
        "lnx-server {}: 名乗り \"{}\"、既知サーバ {} 件",
        serve::VERSION,
        cfg.name,
        cfg.servers.len()
    );

    let port: u16 = cli
        .addr
        .rsplit(':')
        .next()
        .and_then(|p| p.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    let _advertiser = if cli.no_mdns {
        None
    } else {
        match Advertiser::start(&cfg.name, port, serve::VERSION) {
            Ok(a) => Some(a),
            Err(e) => {
                warn!("bonjour を始められない（続行）: {e}");
                None
            }
        }
    };

    // 身元: 一度作った自己署名証明書を使い続ける（アプリはこれを pin する）
    let state_dir = cli
        .state_dir
        .clone()
        .or_else(identity::default_dir)
        .ok_or_else(|| anyhow::anyhow!("証明書の置き場を決められない（--state-dir で指定）"))?;
    let id = ServerIdentity::load_or_create(&state_dir)?;
    info!("証明書: {}", id.cert_path().display());
    let url = identity::pairing_url(&cfg.name, id.cert_der());
    if !cli.no_qr {
        println!(
            "\nlnx creare でこの QR を読むとペアリングする:\n{}",
            identity::render_qr(&url)?
        );
    }
    println!("ペアリング URL: {url}\n");

    let server = serve::build(cfg).await?;
    info!("{} で待ち受け", cli.addr);
    // ここで待つ（常駐の本体）。保存した自己署名証明書で LAN に開く
    Arc::new(server)
        .listener(&cli.addr)
        .cert(id.cert_source())
        .run()
        .await?;
    Ok(())
}
