//! 手元用の listener — ループバックにだけ bind し、ペアリング URL を返す
use std::sync::Arc;

use lnx_server::identity::{ServerIdentity, pairing_url};
use lnx_server::serve;
use serde_json::{Value, json};
use unison::network::ProtocolClient;
use unison::network::quic::QuicClient;

#[tokio::test]
async fn 手元の接続にペアリング_url_を返す() {
    let dir = std::env::temp_dir().join(format!("lnx-local-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let id = ServerIdentity::load_or_create(&dir).unwrap();

    let server = serve::build_local("lnx-test", &id).await.unwrap();
    let handle = Arc::new(server).listener("[::1]:0").spawn().await.unwrap();

    let client = ProtocolClient::new(QuicClient::insecure_localhost().unwrap());
    client
        .connect(&handle.local_addr().to_string())
        .await
        .unwrap();
    let pairing = client.open_channel("pairing").await.unwrap();
    let info: Value = pairing.request("Get", &json!({})).await.unwrap();

    assert_eq!(info["url"], pairing_url("lnx-test", id.cert_der()));
    assert_eq!(info["name"], "lnx-test");
    assert!(
        info["url"]
            .as_str()
            .unwrap()
            .ends_with(info["cert"].as_str().unwrap())
    );

    handle.shutdown().await.unwrap();
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn 手元用の待ち受けはループバックだけを許す() {
    assert!(serve::loopback_only("[::1]:12731").is_ok());
    assert!(serve::loopback_only("127.0.0.1:12731").is_ok());
    assert!(serve::loopback_only("[::]:12731").is_err());
    assert!(serve::loopback_only("0.0.0.0:12731").is_err());
    assert!(serve::loopback_only("192.168.1.2:12731").is_err());
}
