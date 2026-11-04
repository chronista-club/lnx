//! 設定ファイル（TOML）— 名前と、知っているサーバの一覧
use lnx_server::config::{ServerConfig, ServerEntry};

#[test]
fn toml_から名前と既知サーバを読む() {
    let toml = r#"
        name = "lnx-mac"

        [[servers]]
        id = "ladyland.field"
        name = "Ladyland Field"
        kind = "field"
        host = "mako-mac.local"
        port = 7879
    "#;
    let cfg = ServerConfig::from_toml(toml).unwrap();
    assert_eq!(cfg.name, "lnx-mac");
    assert_eq!(
        cfg.servers,
        vec![ServerEntry {
            id: "ladyland.field".into(),
            name: "Ladyland Field".into(),
            kind: "field".into(),
            host: "mako-mac.local".into(),
            port: 7879,
        }]
    );
}

#[test]
fn 既定は名前_lnx_で既知サーバ無し() {
    let cfg = ServerConfig::default();
    assert_eq!(cfg.name, "lnx");
    assert!(cfg.servers.is_empty());
}

#[test]
fn 壊れた_toml_はエラーになる() {
    assert!(ServerConfig::from_toml("name = ").is_err());
}

// --config が無いときは state dir の lnx-server.toml。名乗りは証明書と同じく一度決めたら使い続ける
// （iPad は名乗りで pin を引く。SMAppService の plist は ~ を展開しないので、置き場はサーバが決める）
mod state_dir {
    use lnx_server::config::{CONFIG_FILE, ServerConfig, default_name};

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("lnx-config-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn 無ければ既定の名乗りで作って保存する() {
        let dir = temp_dir("create");
        let (cfg, created) = ServerConfig::load_or_create(&dir, || "lnx-mito-mba".into()).unwrap();
        assert!(created);
        assert_eq!(cfg.name, "lnx-mito-mba");
        assert!(cfg.servers.is_empty());
        // 保存したものを読み直しても同じ
        let saved = ServerConfig::load(&dir.join(CONFIG_FILE)).unwrap();
        assert_eq!(saved, cfg);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn あれば読んで書き換えない() {
        let dir = temp_dir("keep");
        std::fs::create_dir_all(&dir).unwrap();
        let text = "# 手で直した\nname = \"lnx-mac\"\n";
        std::fs::write(dir.join(CONFIG_FILE), text).unwrap();
        let (cfg, created) = ServerConfig::load_or_create(&dir, || "lnx-mito-mba".into()).unwrap();
        assert!(!created);
        assert_eq!(cfg.name, "lnx-mac");
        assert_eq!(
            std::fs::read_to_string(dir.join(CONFIG_FILE)).unwrap(),
            text
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn あれば既定の名乗りを作らない() {
        // 既定の名乗りはホスト名を引く（scutil）。設定があるときは引かない
        let dir = temp_dir("lazy");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(CONFIG_FILE), "name = \"lnx-mac\"\n").unwrap();
        let (cfg, _) = ServerConfig::load_or_create(&dir, || panic!("呼ばない")).unwrap();
        assert_eq!(cfg.name, "lnx-mac");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn 空の設定は名乗りが無いのでエラーにする() {
        // 書きかけで落ちた空のファイルを、黙って名乗り lnx として読まない（iPad の pin が外れる）
        let dir = temp_dir("empty");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(CONFIG_FILE), "").unwrap();
        let err = ServerConfig::load_or_create(&dir, || "lnx-x".into()).unwrap_err();
        let message = format!("{err:#}");
        assert!(message.contains(CONFIG_FILE), "{message}");
        assert!(message.contains("name"), "{message}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn 壊れた設定のエラーにはファイルの場所が出る() {
        let dir = temp_dir("broken");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(CONFIG_FILE), "name = ").unwrap();
        let message = format!(
            "{:#}",
            ServerConfig::load(&dir.join(CONFIG_FILE)).unwrap_err()
        );
        assert!(
            message.contains(&dir.join(CONFIG_FILE).display().to_string()),
            "{message}"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn 作ったあとに一時ファイルを残さない() {
        let dir = temp_dir("tidy");
        ServerConfig::load_or_create(&dir, || "lnx-x".into()).unwrap();
        let names: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        assert_eq!(names, vec![CONFIG_FILE.to_string()]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn 既定の名乗りは_dns_のラベルの上限に収める() {
        // 名乗りは <name>.local. のホスト名にもなる。ラベルは 63 バイトまで
        let name = default_name(Some(&"a".repeat(70)));
        assert!(name.len() <= 63, "{} 文字", name.len());
        assert!(name.starts_with("lnx-a"));
        let name = default_name(Some(&format!("{}-b", "a".repeat(58))));
        assert!(!name.ends_with('-'), "{name}");
    }

    #[test]
    fn 既定の名乗りはホスト名から作る() {
        assert_eq!(default_name(Some("mito-mba")), "lnx-mito-mba");
        assert_eq!(default_name(Some("MakoMBA")), "lnx-makomba");
        assert_eq!(
            default_name(Some("Mako's MacBook Pro")),
            "lnx-mako-s-macbook-pro"
        );
        assert_eq!(default_name(Some("pi.local")), "lnx-pi");
        assert_eq!(default_name(Some("---")), "lnx");
        assert_eq!(default_name(None), "lnx");
    }
}
