use lnx_engine::AudioEngine;
use std::thread;
use std::time::Duration;
use hound;

fn create_test_samples() -> Result<(), Box<dyn std::error::Error>> {
    println!("🎵 Creating test samples...");
    
    // Create samples directory
    std::fs::create_dir_all("samples")?;
    
    // Create kick drum sample (60Hz sine wave)
    create_kick_sample("samples/kick.wav")?;
    
    // Create snare sample (200Hz + noise)
    create_snare_sample("samples/snare.wav")?;
    
    // Create hi-hat sample (8000Hz noise burst)
    create_hihat_sample("samples/hihat.wav")?;
    
    println!("✅ Test samples created");
    Ok(())
}

fn create_kick_sample(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 44100,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    
    let mut writer = hound::WavWriter::create(path, spec)?;
    
    // Generate 0.3 second kick drum (60Hz with decay)
    for sample_idx in 0..(44100 * 3 / 10) {
        let t = sample_idx as f32 / 44100.0;
        let frequency = 60.0;
        let decay = (-t * 8.0).exp(); // Exponential decay
        let amplitude = (t * frequency * 2.0 * std::f32::consts::PI).sin() * decay * 0.8;
        let sample = (amplitude * i16::MAX as f32) as i16;
        writer.write_sample(sample)?;
    }
    
    writer.finalize()?;
    Ok(())
}

fn create_snare_sample(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 44100,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    
    let mut writer = hound::WavWriter::create(path, spec)?;
    
    // Generate 0.2 second snare (200Hz tone + white noise with decay)
    for sample_idx in 0..(44100 * 2 / 10) {
        let t = sample_idx as f32 / 44100.0;
        let decay = (-t * 15.0).exp();
        
        // Tone component
        let tone = (t * 200.0 * 2.0 * std::f32::consts::PI).sin() * 0.3;
        
        // Noise component (simplified)
        let noise = (((sample_idx as f32 * 12.9898).sin() * 43758.5453).fract() - 0.5) * 0.7;
        
        let amplitude = (tone + noise) * decay;
        let sample = (amplitude * i16::MAX as f32) as i16;
        writer.write_sample(sample)?;
    }
    
    writer.finalize()?;
    Ok(())
}

fn create_hihat_sample(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 44100,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    
    let mut writer = hound::WavWriter::create(path, spec)?;
    
    // Generate 0.1 second hi-hat (high frequency noise with quick decay)
    for sample_idx in 0..(44100 / 10) {
        let t = sample_idx as f32 / 44100.0;
        let decay = (-t * 30.0).exp();
        
        // High frequency noise
        let noise = (((sample_idx as f32 * 17.13).sin() * 59341.2176).fract() - 0.5) * 0.5;
        
        let amplitude = noise * decay;
        let sample = (amplitude * i16::MAX as f32) as i16;
        writer.write_sample(sample)?;
    }
    
    writer.finalize()?;
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🥁 LNX Beat Machine Demo with Samples Starting...");
    
    // Create test samples
    create_test_samples()?;
    
    // Initialize audio engine
    let mut engine = AudioEngine::new();
    engine.initialize()?;
    
    println!("✅ Audio engine initialized");
    
    // Load samples into pads
    println!("📂 Loading samples into pads...");
    engine.load_pad_sample(0, "samples/kick.wav")?;   // Kick on pad 0
    engine.load_pad_sample(1, "samples/snare.wav")?;  // Snare on pad 1
    engine.load_pad_sample(2, "samples/hihat.wav")?;  // Hi-hat on pad 2
    println!("✅ Samples loaded");
    
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
            engine.trigger_pad(3, 0.7)?; // Trigger pad 4 manually (no sample loaded)
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
    
    // Clean up samples
    std::fs::remove_dir_all("samples").ok();
    println!("🧹 Cleaned up test samples");
    
    Ok(())
}