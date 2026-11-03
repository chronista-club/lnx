//! 窓を開ける一連 — 実 QUIC で Hello → Welcome、心拍、registry の一覧
use std::sync::Arc;
use std::time::Duration;

use lnx_server::config::ServerConfig;
use lnx_server::serve;
use serde_json::{Value, json};
use unison::network::quic::QuicClient;
use unison::network::{MessageType, ProtocolClient};

const CONFIG: &str = r#"
    name = "lnx-test"

    [[servers]]
    id = "ladyland.field"
    name = "Ladyland Field"
    kind = "field"
    host = "localhost"
    port = 7879
"#;

#[tokio::test]
async fn 窓を開けると名乗りと心拍が来て一覧が引ける() {
    let cfg = ServerConfig::from_toml(CONFIG).unwrap();
    let server = serve::build(cfg).await.unwrap();
    // 待ち受けは空きポートで。cert は既定の dev_localhost（自己署名）
    let handle = Arc::new(server).listener("[::1]:0").spawn().await.unwrap();
    let addr = handle.local_addr();

    // dev_localhost の自己署名を受け入れるクライアント（試験と開発専用）
    let client = ProtocolClient::new(QuicClient::insecure_localhost().unwrap());
    client.connect(&addr.to_string()).await.unwrap();

    // session: Hello → Welcome
    let session = client.open_channel("session").await.unwrap();
    let welcome: Value = session
        .request("Hello", &json!({ "client": "test", "client_version": "0" }))
        .await
        .unwrap();
    assert_eq!(welcome["server_name"], "lnx-test");
    assert!(welcome["server_version"].is_string());
    assert!(welcome["server_time_ms"].as_u64().is_some());

    // Hello のあと 1 秒ちょっとで心拍が来る
    let msg = tokio::time::timeout(Duration::from_millis(2500), session.recv())
        .await
        .expect("心拍が来ない")
        .unwrap();
    assert_eq!(msg.msg_type, MessageType::Event);
    assert_eq!(msg.method, "Heartbeat");
    let hb = msg.payload_as_value().unwrap();
    assert!(hb["seq"].as_u64().is_some());
    assert!(hb["uptime_ms"].as_u64().is_some());

    // registry: List → 設定ファイルの一覧
    let registry = client.open_channel("registry").await.unwrap();
    let list: Value = registry.request("List", &json!({})).await.unwrap();
    assert_eq!(list["servers"][0]["id"], "ladyland.field");
    assert_eq!(list["servers"][0]["port"], 7879);

    handle.shutdown().await.unwrap();
}
