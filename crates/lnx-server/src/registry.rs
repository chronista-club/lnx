//! registry — 知っているサーバの一覧。snapshot で返し、変化は購読者へ押し出す
use std::sync::Arc;

use serde_json::{Value, json};
use tokio::sync::watch;

use crate::config::ServerEntry;

/// 一覧の正本。`snapshot()` が List の応答、`subscribe()` が RegistryChanged の源
#[derive(Clone)]
pub struct Registry {
    tx: Arc<watch::Sender<Value>>,
}

impl Registry {
    pub fn new(entries: Vec<ServerEntry>) -> Self {
        let (tx, _rx) = watch::channel(snapshot_of(&entries));
        Self { tx: Arc::new(tx) }
    }

    /// `{ "servers": [...] }`
    pub fn snapshot(&self) -> Value {
        self.tx.borrow().clone()
    }

    /// 一覧を差し替える。購読者全員に新しい snapshot が届く
    pub fn replace(&self, entries: Vec<ServerEntry>) {
        self.tx.send_replace(snapshot_of(&entries));
    }

    pub fn subscribe(&self) -> watch::Receiver<Value> {
        self.tx.subscribe()
    }
}

fn snapshot_of(entries: &[ServerEntry]) -> Value {
    json!({ "servers": entries })
}
