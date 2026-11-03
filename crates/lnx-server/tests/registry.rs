//! registry — 知っているサーバの一覧。snapshot で返し、変化は購読者へ押し出す
use lnx_server::config::ServerEntry;
use lnx_server::registry::Registry;

fn entry(id: &str) -> ServerEntry {
    ServerEntry {
        id: id.into(),
        name: id.to_uppercase(),
        kind: "field".into(),
        host: "localhost".into(),
        port: 7879,
    }
}

#[test]
fn snapshot_は_servers_配列で返る() {
    let reg = Registry::new(vec![entry("a"), entry("b")]);
    let snap = reg.snapshot();
    let servers = snap["servers"].as_array().expect("servers は配列");
    assert_eq!(servers.len(), 2);
    assert_eq!(servers[0]["id"], "a");
    assert_eq!(servers[0]["name"], "A");
    assert_eq!(servers[0]["kind"], "field");
    assert_eq!(servers[0]["host"], "localhost");
    assert_eq!(servers[0]["port"], 7879);
}

#[tokio::test]
async fn 差し替えると購読者に新しい一覧が届く() {
    let reg = Registry::new(vec![]);
    let mut rx = reg.subscribe();
    reg.replace(vec![entry("c")]);
    rx.changed().await.unwrap();
    assert_eq!(rx.borrow()["servers"][0]["id"], "c");
}
