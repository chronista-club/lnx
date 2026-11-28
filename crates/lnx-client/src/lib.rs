//! アプリ（Vantage Point 等）が `lnx-server` の `gear` channel に接続するための Rust SDK。
pub use lnx_protocol::{self as protocol, wire::*};
use unison::network::{ProtocolClient, QuicClient, TrustAnchors, channel::UnisonChannel};

#[derive(Debug, thiserror::Error)]
#[error("{code}: {message}")]
pub struct RemoteError {
    pub code: String,
    pub message: String,
}

pub struct Client {
    transport: ProtocolClient,
    channel: UnisonChannel,
}

impl Client {
    /// macOS / Unix の既定 endpoint.json パス（`~/Library/Application Support/tech.anycreative.lnx-server/endpoint.json`）
    pub fn default_endpoint_path() -> Option<std::path::PathBuf> {
        std::env::var_os("HOME").map(|home| {
            std::path::PathBuf::from(home)
                .join("Library/Application Support/tech.anycreative.lnx-server/endpoint.json")
        })
    }

    /// 既定の endpoint.json を読み込む。
    pub fn load_default_endpoint() -> anyhow::Result<Endpoint> {
        let path = Self::default_endpoint_path()
            .ok_or_else(|| anyhow::anyhow!("HOME environment variable is not set"))?;
        Self::load_endpoint(&path)
    }

    /// 指定パスの endpoint.json を読み込む。
    pub fn load_endpoint(path: &std::path::Path) -> anyhow::Result<Endpoint> {
        let bytes = std::fs::read(path)?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    /// 既定の endpoint.json から接続する。
    pub async fn connect_default(hello: Hello) -> anyhow::Result<(Self, Snapshot)> {
        let endpoint = Self::load_default_endpoint()?;
        Self::connect(&endpoint, hello).await
    }

    /// 版違いの常駐サービスを停止・上書きしない。再接続と UI はアプリの責務。
    pub async fn connect(
        endpoint: &Endpoint,
        mut hello: Hello,
    ) -> anyhow::Result<(Self, Snapshot)> {
        anyhow::ensure!(
            endpoint.protocol_version == protocol::PROTOCOL_VERSION,
            "incompatible lnx gear protocol"
        );
        let quic = QuicClient::builder()
            .trust_anchors(TrustAnchors::Custom(vec![
                endpoint.certificate_der.clone().into(),
            ]))
            .build()?;
        let transport = ProtocolClient::new(quic);
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            transport.connect(&format!("https://localhost:{}", endpoint.port)),
        )
        .await??;
        let channel = match tokio::time::timeout(
            std::time::Duration::from_secs(3),
            transport.open_channel(CHANNEL),
        )
        .await
        {
            Ok(Ok(channel)) => channel.with_request_timeout(std::time::Duration::from_secs(10)),
            Ok(Err(error)) => {
                let _ = transport.disconnect().await;
                return Err(error.into());
            }
            Err(error) => {
                let _ = transport.disconnect().await;
                return Err(error.into());
            }
        };
        let client = Self { transport, channel };
        hello.auth_token = endpoint.auth_token.clone();
        let result = client.request("Hello", &hello).await;
        match result {
            Ok(snapshot) if snapshot.server_epoch == endpoint.server_epoch => {
                Ok((client, snapshot))
            }
            result => {
                let _ = client.close().await;
                match result {
                    Err(error) => Err(error),
                    Ok(_) => anyhow::bail!("lnx server epoch changed"),
                }
            }
        }
    }

    pub async fn set_enabled(&self, request: &SetEnabled) -> anyhow::Result<Snapshot> {
        self.request("SetEnabled", request).await
    }

    /// SysEx は物理ドライバの completion まで待つ（最大 128 KiB を考慮して 10 秒）。
    pub async fn send_midi(&self, request: &SendMidi) -> anyhow::Result<Snapshot> {
        self.request_with_timeout("SendMidi", request, std::time::Duration::from_secs(10))
            .await
    }

    pub async fn present(&self, request: &Present) -> anyhow::Result<Snapshot> {
        self.request("Present", request).await
    }

    pub async fn snapshot(&self) -> anyhow::Result<Snapshot> {
        self.request("Snapshot", &serde_json::json!({})).await
    }

    /// 自分の setup（Roto 本体の保存枠 0–63 等）を登録する。空で取り消し
    pub async fn set_gear_setups(&self, request: &SetGearSetups) -> anyhow::Result<Snapshot> {
        self.request("SetGearSetups", request).await
    }

    /// lease を持つ間、自分の setup の中で切り替える。受け付けた時点から snapshot の `configuring` が true、
    /// false に戻って `config_error` が無ければ完了
    pub async fn select_setup(&self, request: &SelectSetup) -> anyhow::Result<Snapshot> {
        self.request("SelectSetup", request).await
    }

    /// setup の中身をまるごと書く。完了の見方は `select_setup` と同じ
    pub async fn apply_gear_setup(&self, request: &ApplyGearSetup) -> anyhow::Result<Snapshot> {
        self.request("ApplyGearSetup", request).await
    }

    /// アプリが入力停止・発音整理・出力キュー停止を終えてから明示的に呼ぶ。
    pub async fn quiesced(&self, request: &Quiesced) -> anyhow::Result<Snapshot> {
        self.request("Quiesced", request).await
    }

    pub async fn recv_event(&self) -> anyhow::Result<Event> {
        let message = self.channel.recv().await?;
        Ok(serde_json::from_value(message.payload_as_value()?)?)
    }

    pub async fn close(&self) -> anyhow::Result<()> {
        let _ = self.channel.close().await;
        self.transport.disconnect().await?;
        Ok(())
    }

    async fn request<T: serde::Serialize>(
        &self,
        method: &str,
        request: &T,
    ) -> anyhow::Result<Snapshot> {
        self.request_with_timeout(method, request, std::time::Duration::from_secs(3))
            .await
    }

    async fn request_with_timeout<T: serde::Serialize>(
        &self,
        method: &str,
        request: &T,
        timeout: std::time::Duration,
    ) -> anyhow::Result<Snapshot> {
        let reply: Reply =
            tokio::time::timeout(timeout, self.channel.request(method, request)).await??;
        if let Some(error) = reply.error {
            return Err(RemoteError {
                code: error.code,
                message: error.message,
            }
            .into());
        }
        reply
            .snapshot
            .ok_or_else(|| anyhow::anyhow!("lnx reply missing snapshot"))
    }
}
