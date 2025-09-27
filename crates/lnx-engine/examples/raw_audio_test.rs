use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🔧 Raw Audio Output Test");
    println!("This bypasses the LNX engine and tests direct CPAL audio output");
    
    // Initialize CPAL
    let host = cpal::default_host();
    println!("✅ Audio host: {}", host.id().name());
    
    // Get output device
    let device = host.default_output_device()
        .ok_or("No output device available")?;
    println!("✅ Output device: {}", device.name().unwrap_or_default());
    
    // Get config
    let config = device.default_output_config()?;
    println!("✅ Config: {} Hz, {} channels, {:?}", 
             config.sample_rate().0, 
             config.channels(), 
             config.sample_format());
    
    // Shared state for tone generation
    let sample_clock = Arc::new(AtomicU32::new(0));
    let is_playing = Arc::new(AtomicBool::new(true));
    
    // Clone for callback
    let sample_clock_clone = sample_clock.clone();
    let is_playing_clone = is_playing.clone();
    
    // Create output stream with direct tone generation
    let stream = match config.sample_format() {
        cpal::SampleFormat::F32 => {
            device.build_output_stream(
                &config.config(),
                move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                    if is_playing_clone.load(Ordering::Relaxed) {
                        let sample_rate = 48000.0; // Assume 48kHz
                        for sample in data.iter_mut() {
                            let clock = sample_clock_clone.fetch_add(1, Ordering::Relaxed);
                            let t = clock as f32 / sample_rate;
                            
                            // Generate 440Hz sine wave
                            *sample = (t * 440.0 * 2.0 * std::f32::consts::PI).sin() * 0.3;
                        }
                    } else {
                        // Fill with silence
                        for sample in data.iter_mut() {
                            *sample = 0.0;
                        }
                    }
                },
                |err| eprintln!("Audio stream error: {}", err),
                None
            )?
        }
        _ => return Err("Unsupported sample format".into()),
    };
    
    // Start stream
    stream.play()?;
    println!("🔊 Playing 440Hz tone for 3 seconds...");
    println!("📱 Check your system volume if you don't hear anything!");
    
    // Play for 3 seconds
    thread::sleep(Duration::from_secs(3));
    
    // Stop tone
    is_playing.store(false, Ordering::Relaxed);
    println!("🔇 Stopping tone...");
    
    thread::sleep(Duration::from_millis(500));
    
    // Test short beeps
    println!("📢 Testing short beeps (3 beeps)...");
    for i in 0..3 {
        println!("🔊 Beep {}", i + 1);
        sample_clock.store(0, Ordering::Relaxed); // Reset phase
        is_playing.store(true, Ordering::Relaxed);
        thread::sleep(Duration::from_millis(200)); // 200ms beep
        is_playing.store(false, Ordering::Relaxed);
        thread::sleep(Duration::from_millis(300)); // 300ms silence
    }
    
    println!("✅ Raw audio test completed");
    
    Ok(())
}