use std::path::Path;
use std::sync::Arc;
use std::time::Instant;
use atomic_float::AtomicF32;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

#[derive(Debug, Clone)]
pub struct AudioFileInfo {
    pub path: String,
    pub channels: usize,
    pub sample_rate: u32,
    pub duration_samples: usize,
    pub duration_seconds: f64,
    pub sample_format: SampleFormat,
}

#[derive(Debug, Clone)]
pub enum SampleFormat {
    Int16,
    Int24,
    Float32,
}

#[derive(Debug, Clone)]
pub enum AudioFileError {
    IoError(String),
    FormatError(String),
    UnsupportedFormat(String),
}

impl From<hound::Error> for AudioFileError {
    fn from(err: hound::Error) -> Self {
        AudioFileError::FormatError(err.to_string())
    }
}

impl From<std::io::Error> for AudioFileError {
    fn from(err: std::io::Error) -> Self {
        AudioFileError::IoError(err.to_string())
    }
}

impl From<AudioFileError> for String {
    fn from(err: AudioFileError) -> Self {
        match err {
            AudioFileError::IoError(msg) => format!("IO Error: {}", msg),
            AudioFileError::FormatError(msg) => format!("Format Error: {}", msg),
            AudioFileError::UnsupportedFormat(msg) => format!("Unsupported Format: {}", msg),
        }
    }
}

#[derive(Debug)]
pub struct AudioFilePlayer {
    pub info: AudioFileInfo,
    samples: Vec<Vec<f32>>,  // [channel][sample]
    current_position: AtomicUsize,
    is_playing: AtomicBool,
    is_looping: AtomicBool,
    gain: AtomicF32,
    start_time: Option<Instant>,
}

impl AudioFilePlayer {
    pub fn load_wav<P: AsRef<Path>>(path: P) -> Result<Self, AudioFileError> {
        let path_str = path.as_ref().to_string_lossy().to_string();
        
        let mut reader = hound::WavReader::open(&path)?;
        let spec = reader.spec();
        
        log::info!("Loading WAV file: {}", path_str);
        log::info!("  Channels: {}", spec.channels);
        log::info!("  Sample Rate: {} Hz", spec.sample_rate);
        log::info!("  Bits per Sample: {}", spec.bits_per_sample);
        log::info!("  Sample Format: {:?}", spec.sample_format);
        
        // Convert sample format
        let sample_format = match (spec.sample_format, spec.bits_per_sample) {
            (hound::SampleFormat::Int, 16) => SampleFormat::Int16,
            (hound::SampleFormat::Int, 24) => SampleFormat::Int24,
            (hound::SampleFormat::Float, 32) => SampleFormat::Float32,
            _ => {
                return Err(AudioFileError::UnsupportedFormat(
                    format!("Unsupported format: {} bits, {:?}", 
                           spec.bits_per_sample, spec.sample_format)
                ));
            }
        };
        
        // Read all samples
        let samples_result: Result<Vec<_>, _> = match sample_format {
            SampleFormat::Int16 => {
                reader.samples::<i16>()
                    .map(|s| s.map(|sample| sample as f32 / i16::MAX as f32))
                    .collect()
            }
            SampleFormat::Int24 => {
                reader.samples::<i32>()
                    .map(|s| s.map(|sample| sample as f32 / 8388607.0)) // 2^23 - 1
                    .collect()
            }
            SampleFormat::Float32 => {
                reader.samples::<f32>()
                    .map(|s| s.map(|sample| sample))
                    .collect()
            }
        };
        
        let samples_flat: Vec<f32> = samples_result?;
        let duration_samples = samples_flat.len() / spec.channels as usize;
        let duration_seconds = duration_samples as f64 / spec.sample_rate as f64;
        
        // Deinterleave samples into separate channels
        let mut channels = vec![Vec::with_capacity(duration_samples); spec.channels as usize];
        for (i, sample) in samples_flat.iter().enumerate() {
            let channel = i % spec.channels as usize;
            channels[channel].push(*sample);
        }
        
        let info = AudioFileInfo {
            path: path_str,
            channels: spec.channels as usize,
            sample_rate: spec.sample_rate,
            duration_samples,
            duration_seconds,
            sample_format,
        };
        
        log::info!("Successfully loaded WAV file:");
        log::info!("  Duration: {:.2} seconds ({} samples)", 
                  duration_seconds, duration_samples);
        log::info!("  Memory usage: {:.2} MB", 
                  (samples_flat.len() * 4) as f64 / 1_048_576.0);
        
        Ok(AudioFilePlayer {
            info,
            samples: channels,
            current_position: AtomicUsize::new(0),
            is_playing: AtomicBool::new(false),
            is_looping: AtomicBool::new(false),
            gain: AtomicF32::new(1.0),
            start_time: None,
        })
    }
    
    pub fn play(&mut self) {
        self.current_position.store(0, Ordering::Relaxed); // Reset position to beginning
        self.is_playing.store(true, Ordering::Relaxed);
        self.start_time = Some(Instant::now());
        log::info!("Started playback: {}", self.info.path);
    }
    
    pub fn stop(&mut self) {
        self.is_playing.store(false, Ordering::Relaxed);
        self.current_position.store(0, Ordering::Relaxed);
        self.start_time = None;
        log::info!("Stopped playback: {}", self.info.path);
    }
    
    pub fn pause(&mut self) {
        self.is_playing.store(false, Ordering::Relaxed);
        log::info!("Paused playback: {}", self.info.path);
    }
    
    pub fn resume(&mut self) {
        if self.current_position.load(Ordering::Relaxed) < self.info.duration_samples {
            self.is_playing.store(true, Ordering::Relaxed);
            log::info!("Resumed playback: {}", self.info.path);
        }
    }
    
    pub fn set_position(&mut self, position_samples: usize) {
        let clamped_position = position_samples.min(self.info.duration_samples);
        self.current_position.store(clamped_position, Ordering::Relaxed);
        log::debug!("Set position to {} samples ({:.2}s)", 
                   clamped_position, 
                   clamped_position as f64 / self.info.sample_rate as f64);
    }
    
    pub fn set_position_seconds(&mut self, position_seconds: f64) {
        let position_samples = (position_seconds * self.info.sample_rate as f64) as usize;
        self.set_position(position_samples);
    }
    
    pub fn set_gain(&self, gain: f32) {
        let clamped_gain = gain.clamp(0.0, 2.0);
        self.gain.store(clamped_gain, Ordering::Relaxed);
        log::debug!("Set gain to {:.2}", clamped_gain);
    }
    
    pub fn set_looping(&self, looping: bool) {
        self.is_looping.store(looping, Ordering::Relaxed);
        log::info!("Set looping: {}", looping);
    }
    
    pub fn is_playing(&self) -> bool {
        self.is_playing.load(Ordering::Relaxed)
    }
    
    pub fn is_looping(&self) -> bool {
        self.is_looping.load(Ordering::Relaxed)
    }
    
    pub fn get_position_samples(&self) -> usize {
        self.current_position.load(Ordering::Relaxed)
    }
    
    pub fn get_position_seconds(&self) -> f64 {
        let position_samples = self.current_position.load(Ordering::Relaxed);
        position_samples as f64 / self.info.sample_rate as f64
    }
    
    pub fn get_gain(&self) -> f32 {
        self.gain.load(Ordering::Relaxed)
    }
    
    /// Process audio for the given buffer size
    /// Returns the number of samples actually processed
    pub fn process_audio(&self, output: &mut [Vec<f32>]) -> usize {
        if !self.is_playing.load(Ordering::Relaxed) {
            // Fill with silence
            for channel in output.iter_mut() {
                channel.fill(0.0);
            }
            return 0;
        }
        
        let buffer_size = output[0].len();
        let current_pos = self.current_position.load(Ordering::Relaxed);
        let gain = self.gain.load(Ordering::Relaxed);
        let is_looping = self.is_looping.load(Ordering::Relaxed);
        
        let mut samples_processed = 0;
        let mut position = current_pos;
        
        for frame in 0..buffer_size {
            if position >= self.info.duration_samples {
                if is_looping {
                    position = 0;
                } else {
                    // End of file reached, fill remaining with silence
                    for channel in output.iter_mut() {
                        for i in frame..buffer_size {
                            channel[i] = 0.0;
                        }
                    }
                    // Stop playback
                    self.is_playing.store(false, Ordering::Relaxed);
                    break;
                }
            }
            
            // Copy samples from file to output, applying gain
            for (ch, output_channel) in output.iter_mut().enumerate() {
                if ch < self.samples.len() {
                    output_channel[frame] = self.samples[ch][position] * gain;
                } else {
                    // If output has more channels than source, fill with silence
                    output_channel[frame] = 0.0;
                }
            }
            
            position += 1;
            samples_processed += 1;
        }
        
        // Update position
        self.current_position.store(position, Ordering::Relaxed);
        
        samples_processed
    }
    
    /// Get information about the loaded file
    pub fn get_info(&self) -> &AudioFileInfo {
        &self.info
    }
    
    /// Check if the file has finished playing (and is not looping)
    pub fn is_finished(&self) -> bool {
        !self.is_playing() && 
        self.current_position.load(Ordering::Relaxed) >= self.info.duration_samples
    }
    
    /// Get playback progress as a value between 0.0 and 1.0
    pub fn get_progress(&self) -> f64 {
        let position = self.current_position.load(Ordering::Relaxed);
        if self.info.duration_samples > 0 {
            position as f64 / self.info.duration_samples as f64
        } else {
            0.0
        }
    }
    
    /// Get the remaining time in seconds
    pub fn get_remaining_seconds(&self) -> f64 {
        let position = self.current_position.load(Ordering::Relaxed);
        let remaining_samples = self.info.duration_samples.saturating_sub(position);
        remaining_samples as f64 / self.info.sample_rate as f64
    }
}

// Thread-safe wrapper for AudioFilePlayer
pub type SharedAudioFilePlayer = Arc<std::sync::Mutex<AudioFilePlayer>>;

impl std::fmt::Display for AudioFileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AudioFileError::IoError(msg) => write!(f, "IO Error: {}", msg),
            AudioFileError::FormatError(msg) => write!(f, "Format Error: {}", msg),
            AudioFileError::UnsupportedFormat(msg) => write!(f, "Unsupported Format: {}", msg),
        }
    }
}

impl std::error::Error for AudioFileError {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    
    // Helper function to create a simple test WAV file
    fn create_test_wav(path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: 44100,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        
        let mut writer = hound::WavWriter::create(path, spec)?;
        
        // Generate 1 second of test tone (440 Hz on left, 880 Hz on right)
        for sample_idx in 0..44100 {
            let t = sample_idx as f32 / 44100.0;
            let left_sample = (t * 440.0 * 2.0 * std::f32::consts::PI).sin();
            let right_sample = (t * 880.0 * 2.0 * std::f32::consts::PI).sin();
            
            writer.write_sample((left_sample * i16::MAX as f32) as i16)?;
            writer.write_sample((right_sample * i16::MAX as f32) as i16)?;
        }
        
        writer.finalize()?;
        Ok(())
    }
    
    #[test]
    fn test_wav_loading() {
        let test_path = "/tmp/test_audio.wav";
        create_test_wav(test_path).expect("Failed to create test WAV file");
        
        let player = AudioFilePlayer::load_wav(test_path).expect("Failed to load WAV file");
        
        assert_eq!(player.info.channels, 2);
        assert_eq!(player.info.sample_rate, 44100);
        assert_eq!(player.info.duration_samples, 44100);
        assert!((player.info.duration_seconds - 1.0).abs() < 0.001);
        
        // Clean up
        std::fs::remove_file(test_path).ok();
    }
    
    #[test]
    fn test_playback_control() {
        let test_path = "/tmp/test_audio2.wav";
        create_test_wav(test_path).expect("Failed to create test WAV file");
        
        let mut player = AudioFilePlayer::load_wav(test_path).expect("Failed to load WAV file");
        
        assert!(!player.is_playing());
        
        player.play();
        assert!(player.is_playing());
        
        player.pause();
        assert!(!player.is_playing());
        
        player.resume();
        assert!(player.is_playing());
        
        player.stop();
        assert!(!player.is_playing());
        assert_eq!(player.get_position_samples(), 0);
        
        // Clean up
        std::fs::remove_file(test_path).ok();
    }
    
    #[test]
    fn test_gain_control() {
        let test_path = "/tmp/test_audio3.wav";
        create_test_wav(test_path).expect("Failed to create test WAV file");
        
        let player = AudioFilePlayer::load_wav(test_path).expect("Failed to load WAV file");
        
        assert_eq!(player.get_gain(), 1.0);
        
        player.set_gain(0.5);
        assert_eq!(player.get_gain(), 0.5);
        
        // Test clamping
        player.set_gain(3.0);
        assert_eq!(player.get_gain(), 2.0);
        
        player.set_gain(-0.5);
        assert_eq!(player.get_gain(), 0.0);
        
        // Clean up
        std::fs::remove_file(test_path).ok();
    }
}