//! channel の応対 — session（名乗りと心拍）と registry（一覧と変化）
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::json;
use tokio::task::JoinHandle;
use tracing::{info, warn};
use unison::network::channel::UnisonChannel;
use unison::network::{MessageType, NetworkError, ProtocolServer};

use crate::config::ServerConfig;
use crate::heartbeat::{self, Heartbeat};
use crate::identity::{ServerIdentity, pairing_url};
use crate::registry::Registry;
use crate::{LNX_KDL, LNX_LOCAL_KDL};

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const NAMESPACE: &str = "club.chronista.lnx";

/// 設定から ProtocolServer を組む（registry は設定の一覧で初期化）
pub async fn build(cfg: ServerConfig) -> Result<ProtocolServer, NetworkError> {
    let registry = Registry::new(cfg.servers.clone());
    build_with(cfg, registry, Instant::now()).await
}

/// registry と起動時刻を外から渡す版（差し替えや試験用）
pub async fn build_with(
    cfg: ServerConfig,
    registry: Registry,
    started: Instant,
) -> Result<ProtocolServer, NetworkError> {
    let server = ProtocolServer::with_identity(&cfg.name, VERSION, NAMESPACE);
    server.enable_discovery(LNX_KDL).await?;

    let name = cfg.name.clone();
    server
        .register_channel("session", move |_ctx, stream| {
            let name = name.clone();
            async move { serve_session(name, started, Arc::new(UnisonChannel::new(stream))).await }
        })
        .await;

    server
        .register_channel("registry", move |_ctx, stream| {
            let registry = registry.clone();
            async move { serve_registry(registry, Arc::new(UnisonChannel::new(stream))).await }
        })
        .await;

    Ok(server)
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// session — 接続 1 本ぶんの応対。Hello で名乗り、以後は心拍を流す
async fn serve_session(
    name: String,
    started: Instant,
    channel: Arc<UnisonChannel>,
) -> Result<(), NetworkError> {
    let mut ticker: Option<JoinHandle<()>> = None;
    let result = loop {
        match channel.recv().await {
            Ok(msg) if msg.msg_type == MessageType::Request => match msg.method.as_str() {
                "Hello" => {
                    let payload = msg.payload_as_value().unwrap_or_default();
                    let client = payload
                        .get("client")
                        .and_then(|v| v.as_str())
                        .unwrap_or("?");
                    let client_version = payload
                        .get("client_version")
                        .and_then(|v| v.as_str())
                        .unwrap_or("?");
                    info!("hello: {client} {client_version}");
                    // 心拍は Hello のあとに始める（多重 Hello は張り直さない）
                    if ticker.is_none() {
                        ticker = Some(spawn_heartbeat(channel.clone(), started));
                    }
                    let welcome = json!({
                        "server_name": name,
                        "server_version": VERSION,
                        "server_time_ms": now_ms(),
                    });
                    if let Err(e) = channel.send_response(msg.id, &msg.method, &welcome).await {
                        break Err(e);
                    }
                }
                other => warn!("session: 未知の request {other}"),
            },
            Ok(_) => continue,
            Err(e) if e.is_normal_close() => break Ok(()),
            Err(e) => break Err(e),
        }
    };
    if let Some(t) = ticker.take() {
        t.abort();
    }
    info!("session: 閉じた");
    result
}

/// 1 秒ごとの心拍。最初の 1 拍は即座に（開いた瞬間に脈が見える）
fn spawn_heartbeat(channel: Arc<UnisonChannel>, started: Instant) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(heartbeat::PERIOD);
        let mut seq: u64 = 0;
        loop {
            interval.tick().await;
            seq += 1;
            let beat = Heartbeat {
                seq,
                uptime: started.elapsed(),
            };
            if channel
                .send_event("Heartbeat", &beat.to_value())
                .await
                .is_err()
            {
                break; // 接続が閉じた
            }
        }
    })
}

/// registry — List で snapshot、変化は RegistryChanged で押し出す
async fn serve_registry(
    registry: Registry,
    channel: Arc<UnisonChannel>,
) -> Result<(), NetworkError> {
    let mut rx = registry.subscribe();
    let sender = channel.clone();
    let pusher = tokio::spawn(async move {
        while rx.changed().await.is_ok() {
            let snapshot = rx.borrow_and_update().clone();
            if sender
                .send_event("RegistryChanged", &snapshot)
                .await
                .is_err()
            {
                break;
            }
        }
    });
    let result = loop {
        match channel.recv().await {
            Ok(msg) if msg.msg_type == MessageType::Request => match msg.method.as_str() {
                "List" => {
                    if let Err(e) = channel
                        .send_response(msg.id, &msg.method, &registry.snapshot())
                        .await
                    {
                        break Err(e);
                    }
                }
                other => warn!("registry: 未知の request {other}"),
            },
            Ok(_) => continue,
            Err(e) if e.is_normal_close() => break Ok(()),
            Err(e) => break Err(e),
        }
    };
    pusher.abort();
    result
}

#[allow(dead_code)]
const _: Duration = heartbeat::PERIOD;

/// 手元用のサーバ（pairing channel だけ）。ループバックにだけ bind して使う（`loopback_only`）
pub async fn build_local(name: &str, id: &ServerIdentity) -> Result<ProtocolServer, NetworkError> {
    let server = ProtocolServer::with_identity(name, VERSION, "club.chronista.lnx.local");
    server.enable_discovery(LNX_LOCAL_KDL).await?;
    let url = pairing_url(name, id.cert_der());
    let cert = url.rsplit("cert=").next().unwrap_or_default().to_string();
    let info = json!({ "url": url, "name": name, "cert": cert });
    server
        .register_channel("pairing", move |_ctx, stream| {
            let info = info.clone();
            async move {
                let channel = UnisonChannel::new(stream);
                loop {
                    match channel.recv().await {
                        Ok(msg) if msg.msg_type == MessageType::Request => {
                            match msg.method.as_str() {
                                "Get" => channel.send_response(msg.id, &msg.method, &info).await?,
                                other => warn!("pairing: 未知の request {other}"),
                            }
                        }
                        Ok(_) => continue,
                        Err(e) if e.is_normal_close() => return Ok(()),
                        Err(e) => return Err(e),
                    }
                }
            }
        })
        .await;
    Ok(server)
}

/// 手元用の待ち受けアドレスがループバックかを確かめる（LAN に開いてしまわないように）
pub fn loopback_only(addr: &str) -> anyhow::Result<std::net::SocketAddr> {
    let parsed: std::net::SocketAddr = addr
        .parse()
        .map_err(|e| anyhow::anyhow!("{addr} を読めない: {e}"))?;
    if !parsed.ip().is_loopback() {
        anyhow::bail!(
            "手元用の待ち受け {addr} はループバックではない（[::1] か 127.0.0.1 にする）"
        );
    }
    Ok(parsed)
}
