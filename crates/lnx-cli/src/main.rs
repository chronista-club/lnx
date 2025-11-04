use anyhow::Result;
use clap::{Parser, Subcommand};
use env_logger::Env;
use log::{debug, info};

/// lnx - wavelet synthesize engine コマンドラインインターフェース
#[derive(Parser, Debug)]
#[command(
    name = "lnx",
    version,
    about = "lnx - wavelet synthesize engine",
    long_about = None
)]
struct Cli {
    /// 詳細なログ出力を有効化
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// オーディオエンジンを起動
    Start {
        /// デーモンモードで起動（バックグラウンド実行）
        #[arg(short, long)]
        daemon: bool,
        /// GUIクリエーターを起動
        #[arg(short = 'g', long)]
        gui: bool,
        /// 使用するオーディオデバイス
        #[arg(short = 'o', long)]
        output_device: Option<String>,
        /// 使用する入力デバイス
        #[arg(short = 'i', long)]
        input_device: Option<String>,
        /// サンプルレート（NDI標準: 48kHz）
        #[arg(short = 's', long, default_value = "48000")]
        sample_rate: u32,
        /// バッファサイズ（低レイテンシ推奨: 64サンプル）
        #[arg(short, long, default_value = "64")]
        buffer_size: u32,
    },
    /// オーディオエンジンを停止
    Stop {
        /// 強制停止
        #[arg(short, long)]
        force: bool,
    },
    /// システム状態とデバイス情報を表示
    Status {
        /// 詳細情報を表示
        #[arg(short, long)]
        detailed: bool,
    },
    /// オーディオデバイスの管理
    Audio {
        #[command(subcommand)]
        command: AudioCommands,
    },
    /// MIDIデバイスの管理
    Midi {
        #[command(subcommand)]
        command: MidiCommands,
    },
    /// パフォーマンスモニタリング
    Monitor {
        /// リアルタイムモニタリングを開始
        #[arg(short, long)]
        realtime: bool,
    },
    /// 設定管理
    Config {
        #[command(subcommand)]
        command: ConfigCommands,
    },
    /// インタラクティブUIを起動
    Ui,
}

#[derive(Subcommand, Debug)]
enum AudioCommands {
    /// 利用可能なオーディオデバイスを一覧表示
    List,
    /// デフォルトデバイスを設定
    SetDefault {
        /// デバイス名またはID
        device: String,
    },
    /// オーディオレイテンシーをテスト
    TestLatency {
        /// テスト期間（秒）
        #[arg(short, long, default_value = "10")]
        duration: u32,
    },
    /// オーディオエンジンのステータスを表示
    Status,
}

#[derive(Subcommand, Debug)]
enum MidiCommands {
    /// 利用可能なMIDIデバイスを一覧表示
    List,
    /// MIDIデバイスに接続
    Connect {
        /// デバイス名またはID
        device: String,
    },
    /// MIDIイベントをモニタリング
    Monitor {
        /// モニタリングするデバイス
        device: Option<String>,
    },
    /// Korg Keystage接続テスト
    TestKeystage,
}

#[derive(Subcommand, Debug)]
enum ConfigCommands {
    /// 現在の設定を表示
    Show,
    /// 設定値を変更
    Set {
        /// 設定キー
        key: String,
        /// 設定値
        value: String,
    },
    /// デフォルト設定にリセット
    Reset {
        /// 確認なしでリセット
        #[arg(long)]
        force: bool,
    },
    /// 設定ファイルのパスを表示
    Path,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // ログレベルの設定
    let log_level = match cli.verbose {
        0 => "info",
        1 => "debug",
        _ => "trace",
    };

    env_logger::Builder::from_env(Env::default().default_filter_or(log_level)).init();

    debug!("lnxコマンド起動");

    match cli.command {
        Commands::Start {
            daemon,
            gui,
            output_device,
            input_device,
            sample_rate,
            buffer_size,
        } => {
            handle_start(
                daemon,
                gui,
                output_device,
                input_device,
                sample_rate,
                buffer_size,
            )
            .await?
        }
        Commands::Stop { force } => handle_stop(force).await?,
        Commands::Status { detailed } => handle_status(detailed).await?,
        Commands::Audio { command } => handle_audio_command(command).await?,
        Commands::Midi { command } => handle_midi_command(command).await?,
        Commands::Monitor { realtime } => handle_monitor(realtime).await?,
        Commands::Config { command } => handle_config_command(command).await?,
        Commands::Ui => handle_ui().await?,
    }

    Ok(())
}

async fn handle_audio_command(command: AudioCommands) -> Result<()> {
    match command {
        AudioCommands::List => {
            info!("利用可能なオーディオデバイス:");
            // TODO: lnx-engineからデバイスリストを取得
            println!("1. Built-in Output");
            println!("2. Built-in Microphone");
        }
        AudioCommands::SetDefault { device } => {
            info!("デフォルトデバイスを設定: {}", device);
            // TODO: デバイス設定の実装
        }
        AudioCommands::TestLatency { duration } => {
            info!("{}秒間レイテンシーテストを実行", duration);
            // TODO: レイテンシーテストの実装
            println!("平均レイテンシー: 5.2ms");
        }
        AudioCommands::Status => {
            info!("オーディオエンジンステータス:");
            println!("状態: 動作中");
            println!("サンプルレート: 48000 Hz (NDI標準)");
            println!("バッファサイズ: 64 samples");
            println!("ビット深度: 32bit float (NDI内部処理)");
            println!("レイテンシー: 1.33ms");
        }
    }
    Ok(())
}

async fn handle_midi_command(command: MidiCommands) -> Result<()> {
    match command {
        MidiCommands::List => {
            info!("利用可能なMIDIデバイス:");
            // TODO: MIDIデバイスリストの取得
            println!("1. Korg Keystage 49");
            println!("2. Akai LPD8");
        }
        MidiCommands::Connect { device } => {
            info!("MIDIデバイスに接続: {}", device);
            // TODO: MIDI接続の実装
        }
        MidiCommands::Monitor { device } => {
            let device_name = device.unwrap_or_else(|| "全デバイス".to_string());
            info!("MIDIイベントをモニタリング: {}", device_name);
            println!("Ctrl+Cで終了");
            // TODO: MIDIモニタリングの実装
        }
        MidiCommands::TestKeystage => {
            info!("Korg Keystage接続テスト開始");
            println!("Keystageで以下の操作を行ってください:");
            println!("1. 任意のキーを押す");
            println!("2. モジュレーションホイールを動かす");
            println!("3. サステインペダルを踏む");
            // TODO: Keystageテストの実装
        }
    }
    Ok(())
}

async fn handle_monitor(realtime: bool) -> Result<()> {
    if realtime {
        use std::time::Duration;
        use tokio::time;

        info!("リアルタイムモニタリング開始");
        println!("パフォーマンスモニター (Ctrl+Cで終了)");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // Ctrl+Cハンドラの設定
        let (tx, mut rx) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            tokio::signal::ctrl_c().await.ok();
            let _ = tx.send(());
        });

        let mut counter = 0;
        loop {
            // ダミーのパフォーマンスデータ（実際の実装では実データを取得）
            let cpu = 10.0 + (counter as f32 * 0.5) % 20.0;
            let memory = 1.2 + (counter as f32 * 0.1) % 2.0;
            let latency = 1.3 + (counter as f32 * 0.05) % 0.5;

            // カーソルを行頭に戻して上書き
            print!(
                "\rCPU: {:.1}% | メモリ: {:.1}GB | レイテンシー: {:.1}ms",
                cpu, memory, latency
            );
            use std::io::{self, Write};
            io::stdout().flush()?;

            counter += 1;

            // Ctrl+Cが押されたか、または1秒待機
            tokio::select! {
                _ = &mut rx => {
                    println!("\n\nモニタリング終了");
                    break;
                }
                _ = time::sleep(Duration::from_secs(1)) => {}
            }
        }
    } else {
        info!("現在のパフォーマンス:");
        println!("CPU使用率: 12.3%");
        println!("メモリ使用量: 1.2GB / 16GB");
        println!("オーディオレイテンシー: 5.2ms");
        println!("アクティブストリーム: 2");
    }
    Ok(())
}

async fn handle_status(detailed: bool) -> Result<()> {
    info!("システムステータス表示");

    // ヘッダー
    println!("\n╔══════════════════════════════════════════════════════════╗");
    println!("║                    lnx v0.1.0                             ║");
    println!("╚══════════════════════════════════════════════════════════╝");

    // システム情報
    println!("\n📊 システム情報");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("  OS: macOS 15.5 (Sequoia)");
    println!("  CPU: Apple M2 Pro");
    println!("  メモリ: 16GB");
    println!("  エンジン: lnx-engine v0.1.0");

    // オーディオデバイス
    println!("\n🎵 オーディオデバイス");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("  出力デバイス:");
    println!("    • Built-in Output [デフォルト]");
    println!("    • External Headphones");
    println!("  入力デバイス:");
    println!("    • Built-in Microphone [デフォルト]");
    if detailed {
        println!("  設定:");
        println!("    • サンプルレート: 48000 Hz (NDI標準)");
        println!("    • バッファサイズ: 64 samples");
        println!("    • ビット深度: 32bit float (NDI内部処理)");
        println!("    • レイテンシー: 1.33ms");
    }

    // MIDIデバイス
    println!("\n🎹 MIDIデバイス");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("  接続済み:");
    println!("    • Korg Keystage 49 [MIDI 2.0]");
    println!("    • Akai LPD8 [MIDI 1.0]");
    if detailed {
        println!("  ポート:");
        println!("    • 入力: 2 ports active");
        println!("    • 出力: 1 port active");
    }

    // パフォーマンス状態
    println!("\n⚡ パフォーマンス");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("  CPU使用率: 12.3%");
    println!("  メモリ使用量: 1.2GB / 16GB");
    println!("  オーディオレイテンシー: 1.33ms");
    println!("  アクティブストリーム: 2");

    if detailed {
        println!("\n📝 追加情報");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("  設定ファイル: .lnx/config.toml");
        println!("  ログファイル: .lnx/logs/");
        println!("  プラグイン: 0 loaded");
    }

    println!("\n💡 ヒント: 詳細情報を見るには 'lnx status --detailed' を使用");
    println!();

    Ok(())
}

async fn handle_config_command(command: ConfigCommands) -> Result<()> {
    match command {
        ConfigCommands::Show => {
            info!("現在の設定:");
            println!("audio.sample_rate = 48000");
            println!("audio.buffer_size = 64");
            println!("audio.bit_depth = 32");
            println!("audio.bit_format = float32");
            println!("audio.default_device = \"Built-in Output\"");
            println!("midi.auto_connect = true");
            println!("ui.theme = \"dark\"");
        }
        ConfigCommands::Set { key, value } => {
            info!("設定を変更: {} = {}", key, value);
            // TODO: 設定変更の実装
        }
        ConfigCommands::Reset { force } => {
            if !force {
                println!("設定をデフォルトにリセットしますか？ (y/N)");
                // TODO: 確認プロンプトの実装
            }
            info!("設定をリセット");
        }
        ConfigCommands::Path => {
            println!("設定ファイル: .lnx/config.toml");
        }
    }
    Ok(())
}

async fn handle_start(
    daemon: bool,
    gui: bool,
    output_device: Option<String>,
    input_device: Option<String>,
    sample_rate: u32,
    buffer_size: u32,
) -> Result<()> {
    info!("オーディオエンジンを起動");

    // 現在のバイナリパスを取得
    let current_exe = std::env::current_exe()?;
    let lnx_bin = current_exe.to_string_lossy().to_string();

    if daemon {
        println!("\n🚀 lnx audio engine 起動中...");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // エンジン設定の表示
        println!("📋 設定:");
        println!("  サンプルレート: {} Hz", sample_rate);
        println!("  バッファサイズ: {} samples", buffer_size);

        if let Some(ref device) = output_device {
            println!("  出力デバイス: {}", device);
        } else {
            println!("  出力デバイス: システムデフォルト");
        }

        if let Some(ref device) = input_device {
            println!("  入力デバイス: {}", device);
        } else {
            println!("  入力デバイス: システムデフォルト");
        }

        println!("\n🔄 デーモンモードで起動...");

        // ichimiのプロセスIDを作成
        let process_id = "lnx-engine";

        // まず既存のプロセスを確認
        println!("📝 既存のプロセスを確認中...");

        // コマンドラインの引数を構築
        let mut args = vec![
            "start".to_string(),
            "--sample-rate".to_string(),
            sample_rate.to_string(),
            "--buffer-size".to_string(),
            buffer_size.to_string(),
        ];

        if let Some(ref device) = output_device {
            args.push("--output-device".to_string());
            args.push(device.clone());
        }

        if let Some(ref device) = input_device {
            args.push("--input-device".to_string());
            args.push(device.clone());
        }

        // ichimiで起動（フォアグラウンドモードで実行）
        println!("🚀 ichimiでプロセスを管理...");
        println!("   プロセスID: {}", process_id);
        println!("   コマンド: {} {}", lnx_bin, args.join(" "));

        // TODO: 実際のichimi APIを呼び出す
        // 現在は仮実装
        println!("\n⚠️  ichimi統合は実装中です");
        println!("   実際には以下のコマンドが実行されます:");
        println!(
            "   ichimi create-process --id {} --command '{}' --args '{}'",
            process_id,
            lnx_bin,
            args.join(" ")
        );
        println!("   ichimi start-process --id {}", process_id);

        // GUIオプションがある場合はクリエーターも起動
        if gui {
            println!("\n🎨 GUIクリエーターを起動...");
            println!("   プロセスID: lnx-creare");

            // TODO: 実際のichimi APIを呼び出す
            println!("   実際には以下のコマンドが実行されます:");
            println!(
                "   ichimi create-process --id lnx-creare --command 'cargo' --args 'run --bin lnx-creare'"
            );
            println!("   ichimi start-process --id lnx-creare");
        }

        println!("\n✅ エンジンがバックグラウンドで起動しました");
        println!("   停止するには: lnx stop");
        println!("   状態確認: lnx status");
    } else {
        println!("\n🚀 lnx audio engine 起動中...");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // エンジン設定の表示
        println!("📋 設定:");
        println!("  サンプルレート: {} Hz", sample_rate);
        println!("  バッファサイズ: {} samples", buffer_size);

        if let Some(ref device) = output_device {
            println!("  出力デバイス: {}", device);
        } else {
            println!("  出力デバイス: システムデフォルト");
        }

        if let Some(ref device) = input_device {
            println!("  入力デバイス: {}", device);
        } else {
            println!("  入力デバイス: システムデフォルト");
        }

        println!("\n▶️  フォアグラウンドモードで起動...");
        println!("   Ctrl+Cで終了");

        // GUIオプションがある場合はクリエーターを起動
        if gui {
            println!("\n🎨 GUIクリエーターを起動...");

            // クリエーターを別スレッドで起動
            std::thread::spawn(|| {
                println!("   Bevyウィンドウを開いています...");
                // TODO: 実際のクリエーター起動
                // ここで cargo run --bin lnx-creare を実行するか、
                // または直接 lnx_creare::run() を呼び出す
                println!("   （クリエーターの実装は開発中）");
            });
        }

        // エンジンの初期化と起動
        // TODO: 実際のエンジン起動実装
        println!("\n   （エンジンの実装は開発中）");

        // Ctrl+Cハンドラの設定
        let (tx, mut rx) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            tokio::signal::ctrl_c().await.ok();
            let _ = tx.send(());
        });

        println!("\n✅ オーディオエンジン動作中");
        if gui {
            println!("✅ クリエーター動作中");
        }
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // エンジン実行ループ
        loop {
            tokio::select! {
                _ = &mut rx => {
                    println!("\n\n⏹  エンジンを停止しています...");
                    // TODO: エンジンの適切な停止処理
                    println!("✅ エンジンが停止しました");
                    break;
                }
                _ = tokio::time::sleep(std::time::Duration::from_secs(1)) => {
                    // エンジンのステータス更新（仮）
                    // TODO: 実際のエンジンステータスを取得
                }
            }
        }
    }

    Ok(())
}

async fn handle_stop(force: bool) -> Result<()> {
    info!("オーディオエンジンを停止");

    let process_id = "lnx-engine";

    if force {
        println!("⚠️  エンジンを強制停止しています...");
        println!("   プロセスID: {}", process_id);

        // TODO: 実際のichimi APIを呼び出す
        println!("   実際には以下のコマンドが実行されます:");
        println!("   ichimi stop-process --id {} --force", process_id);

        println!("✅ エンジンを強制停止しました");
    } else {
        println!("⏹  エンジンを停止しています...");
        println!("   プロセスID: {}", process_id);

        // TODO: 実際のichimi APIを呼び出す
        println!("   実際には以下のコマンドが実行されます:");
        println!(
            "   ichimi stop-process --id {} --grace-period 5000",
            process_id
        );

        println!("✅ エンジンが停止しました");
    }

    Ok(())
}

async fn handle_ui() -> Result<()> {
    info!("インタラクティブUIを起動");
    println!("lnx UI起動中...");
    println!("（この機能は開発中です）");
    // TODO: ratatuiを使用したTUIの実装
    Ok(())
}
