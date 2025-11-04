use bevy::prelude::*;
use bevy::window::WindowMode;

fn main() {
    println!("🎨 lnx creare 起動中...");

    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "lnx creare".to_string(),
                resolution: (1280.0, 720.0).into(),
                mode: WindowMode::Windowed,
                ..default()
            }),
            ..default()
        }))
        .insert_resource(ClearColor(Color::srgb(0.1, 0.1, 0.15)))
        .add_systems(Startup, setup)
        .add_systems(Update, update_system)
        .run();
}

fn setup(mut commands: Commands) {
    println!("📷 カメラセットアップ");

    // 2Dカメラ
    commands.spawn(Camera2dBundle::default());

    // タイトルテキスト
    commands.spawn(
        TextBundle::from_section(
            "lnx creare",
            TextStyle {
                font_size: 48.0,
                color: Color::WHITE,
                ..default()
            },
        )
        .with_style(Style {
            position_type: PositionType::Absolute,
            top: Val::Px(20.0),
            left: Val::Px(20.0),
            ..default()
        }),
    );

    // ステータステキスト
    commands.spawn((
        TextBundle::from_section(
            "Status: Ready",
            TextStyle {
                font_size: 24.0,
                color: Color::srgb(0.0, 1.0, 0.5),
                ..default()
            },
        )
        .with_style(Style {
            position_type: PositionType::Absolute,
            bottom: Val::Px(20.0),
            left: Val::Px(20.0),
            ..default()
        }),
        StatusText,
    ));

    println!("✅ セットアップ完了");
}

// ステータステキスト用のマーカーコンポーネント
#[derive(Component)]
struct StatusText;

// フレームカウンター
#[derive(Resource)]
struct FrameCounter {
    count: u32,
}

impl Default for FrameCounter {
    fn default() -> Self {
        Self { count: 0 }
    }
}

fn update_system(mut frame_counter: Local<u32>, mut query: Query<&mut Text, With<StatusText>>) {
    *frame_counter += 1;

    // 60フレームごと（約1秒）にコンソール出力
    if *frame_counter % 60 == 0 {
        println!("🔄 Frame: {}", *frame_counter);

        // ステータステキストも更新
        for mut text in &mut query {
            text.sections[0].value = format!("Frame: {} | FPS: ~60", *frame_counter);
        }
    }
}
