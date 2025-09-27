use lnx_engine::AudioEngine;
use std::thread;
use std::time::Duration;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🔊 Simple Tone Test Starting...");
    
    // Initialize audio engine
    let mut engine = AudioEngine::new();
    engine.initialize()?;
    println!("✅ Audio engine initialized");
    
    // Start audio processing
    engine.start()?;
    println!("✅ Audio processing started");
    
    println!("🎵 Test will run for 3 seconds with manual pad triggers...");
    println!("📱 Make sure your system volume is up!");
    
    // Create test samples
    std::fs::create_dir_all("samples")?;
    create_loud_test_tone("samples/test_tone.wav")?;
    
    // Load sample into pad
    engine.load_pad_sample(0, "samples/test_tone.wav")?;
    println!("✅ Test tone loaded into pad 0");
    
    // Test manual pad triggers every 500ms
    for i in 0..6 {
        println!("🔊 Trigger #{} - Manual pad trigger!", i + 1);
        engine.trigger_pad(0, 1.0)?;
        thread::sleep(Duration::from_millis(500));
    }
    
    println!("⏹️  Test completed");
    engine.stop()?;
    
    // Clean up
    std::fs::remove_dir_all("samples").ok();
    
    Ok(())
}

fn create_loud_test_tone(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    use hound;
    
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 48000, // Match system sample rate
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    
    let mut writer = hound::WavWriter::create(path, spec)?;
    
    // Generate 0.5 second loud 440Hz tone
    for sample_idx in 0..(48000 / 2) {
        let t = sample_idx as f32 / 48000.0;
        let frequency = 440.0; // A4 note
        let amplitude = (t * frequency * 2.0 * std::f32::consts::PI).sin() * 0.9; // Very loud
        let sample = (amplitude * i16::MAX as f32) as i16;
        writer.write_sample(sample)?;
    }
    
    writer.finalize()?;
    println!("✅ Created loud test tone at {}", path);
    Ok(())
}