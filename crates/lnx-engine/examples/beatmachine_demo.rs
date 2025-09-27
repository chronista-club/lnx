use lnx_engine::{AudioEngine, BeatMachine};
use std::thread;
use std::time::Duration;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🥁 LNX Beat Machine Demo Starting...");
    
    // Initialize audio engine
    let mut engine = AudioEngine::new();
    engine.initialize()?;
    
    println!("✅ Audio engine initialized");
    
    // Start audio processing
    engine.start()?;
    println!("✅ Audio processing started");
    
    // Get initial beatmachine status
    match engine.get_beatmachine_status() {
        Ok((playing, step, bpm)) => {
            println!("📊 Initial Status: Playing={}, Step={}, BPM={}", playing, step, bpm);
        },
        Err(e) => println!("❌ Error getting status: {}", e),
    }
    
    // Set BPM to 120
    engine.set_beatmachine_bpm(120.0)?;
    println!("🎵 BPM set to 120");
    
    // Create a simple 4/4 kick pattern
    println!("🎯 Creating 4/4 kick pattern...");
    engine.set_beatmachine_step(0, 0, true, 1.0)?;  // Beat 1
    engine.set_beatmachine_step(4, 0, true, 0.8)?;  // Beat 2
    engine.set_beatmachine_step(8, 0, true, 1.0)?;  // Beat 3
    engine.set_beatmachine_step(12, 0, true, 0.8)?; // Beat 4
    
    // Add snare on beats 2 and 4
    println!("🥁 Adding snare pattern...");
    engine.set_beatmachine_step(4, 1, true, 0.9)?;  // Beat 2 snare
    engine.set_beatmachine_step(12, 1, true, 0.9)?; // Beat 4 snare
    
    // Add hi-hat pattern
    println!("🎩 Adding hi-hat pattern...");
    for step in [1, 3, 5, 7, 9, 11, 13, 15] {
        engine.set_beatmachine_step(step, 2, true, 0.6)?;
    }
    
    println!("🚀 Starting beatmachine playback...");
    engine.play_beatmachine()?;
    
    // Monitor playback for 10 seconds
    for i in 0..20 {
        thread::sleep(Duration::from_millis(500));
        
        match engine.get_beatmachine_status() {
            Ok((playing, step, bpm)) => {
                println!("📈 #{:2} Playing={}, Current Step={:2}, BPM={}", 
                         i+1, playing, step, bpm);
            },
            Err(e) => println!("❌ Error: {}", e),
        }
        
        // Test manual pad triggers every 2 seconds
        if i % 4 == 0 && i > 0 {
            println!("👆 Manual pad trigger test...");
            engine.trigger_pad(3, 0.7)?; // Trigger pad 4 manually
        }
        
        // Change BPM at halfway point
        if i == 10 {
            println!("🔄 Changing BPM to 140...");
            engine.set_beatmachine_bpm(140.0)?;
        }
    }
    
    println!("⏹️  Stopping beatmachine...");
    engine.stop_beatmachine()?;
    
    // Final status check
    match engine.get_beatmachine_status() {
        Ok((playing, step, bpm)) => {
            println!("📊 Final Status: Playing={}, Step={}, BPM={}", playing, step, bpm);
        },
        Err(e) => println!("❌ Error getting final status: {}", e),
    }
    
    engine.stop()?;
    println!("✅ Demo completed successfully!");
    
    Ok(())
}