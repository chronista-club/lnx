use lnx_engine::AudioEngine;
use std::thread;
use std::time::Duration;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🔍 Audio Debug Test Starting...");
    
    // Initialize audio engine
    let mut engine = AudioEngine::new();
    engine.initialize()?;
    println!("✅ Audio engine initialized");
    
    // Start audio processing
    engine.start()?;
    println!("✅ Audio processing started");
    
    // Create test samples
    std::fs::create_dir_all("samples")?;
    create_debug_tone("samples/debug_tone.wav")?;
    
    // Load sample into pad
    engine.load_pad_sample(0, "samples/debug_tone.wav")?;
    println!("✅ Debug tone loaded into pad 0");
    
    println!("🔊 Triggering pad manually (should hear sound now)...");
    
    // Trigger pad multiple times with delay
    for i in 0..5 {
        println!("🎵 Trigger {} - Playing pad 0...", i + 1);
        engine.trigger_pad(0, 1.0)?;
        
        // Wait longer between triggers to hear each one clearly
        thread::sleep(Duration::from_millis(1000));
    }
    
    println!("⏹️  Test completed");
    engine.stop()?;
    
    // Clean up
    std::fs::remove_dir_all("samples").ok();
    
    Ok(())
}

fn create_debug_tone(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    use hound;
    
    let spec = hound::WavSpec {
        channels: 2, // Stereo
        sample_rate: 48000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    
    let mut writer = hound::WavWriter::create(path, spec)?;
    
    println!("🎵 Creating debug tone: 1kHz sine wave, 1 second duration");
    
    // Generate 1 second 1kHz sine wave (very audible frequency)
    for sample_idx in 0..48000 {
        let t = sample_idx as f32 / 48000.0;
        let frequency = 1000.0; // 1kHz - very audible
        let amplitude = (t * frequency * 2.0 * std::f32::consts::PI).sin() * 0.8;
        let sample = (amplitude * i16::MAX as f32 * 0.8) as i16;
        
        // Write stereo samples (left and right)
        writer.write_sample(sample)?; // Left
        writer.write_sample(sample)?; // Right
    }
    
    writer.finalize()?;
    println!("✅ Created 1kHz debug tone: {} (48kHz stereo, 1 second)", path);
    Ok(())
}