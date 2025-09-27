use std::collections::VecDeque;

pub trait AudioEffect: Send + Sync {
    fn process(&mut self, input: &[f32], output: &mut [f32]);
    fn reset(&mut self);
    fn set_parameter(&mut self, param: &str, value: f32);
    fn get_parameter(&self, param: &str) -> Option<f32>;
}

// Simple delay effect
pub struct Delay {
    buffer: VecDeque<f32>,
    delay_samples: usize,
    feedback: f32,
    mix: f32,
    sample_rate: f32,
}

impl Delay {
    pub fn new(sample_rate: f32) -> Self {
        let max_delay = (sample_rate * 2.0) as usize; // 2 seconds max delay
        Self {
            buffer: VecDeque::with_capacity(max_delay),
            delay_samples: (sample_rate * 0.25) as usize, // 250ms default
            feedback: 0.3,
            mix: 0.5,
            sample_rate,
        }
    }
    
    pub fn set_delay_time(&mut self, time_ms: f32) {
        self.delay_samples = ((time_ms / 1000.0) * self.sample_rate) as usize;
        self.delay_samples = self.delay_samples.min(self.buffer.capacity());
    }
}

impl AudioEffect for Delay {
    fn process(&mut self, input: &[f32], output: &mut [f32]) {
        for (i, &sample) in input.iter().enumerate() {
            // Get delayed sample
            let delayed = if self.buffer.len() >= self.delay_samples {
                self.buffer[self.buffer.len() - self.delay_samples]
            } else {
                0.0
            };
            
            // Calculate output with feedback
            let wet = delayed;
            let feedback_sample = sample + delayed * self.feedback;
            
            // Add to delay buffer
            self.buffer.push_back(feedback_sample);
            if self.buffer.len() > self.buffer.capacity() {
                self.buffer.pop_front();
            }
            
            // Mix dry and wet signals
            output[i] = sample * (1.0 - self.mix) + wet * self.mix;
        }
    }
    
    fn reset(&mut self) {
        self.buffer.clear();
    }
    
    fn set_parameter(&mut self, param: &str, value: f32) {
        match param {
            "delay_time" => self.set_delay_time(value),
            "feedback" => self.feedback = value.clamp(0.0, 0.95),
            "mix" => self.mix = value.clamp(0.0, 1.0),
            _ => {}
        }
    }
    
    fn get_parameter(&self, param: &str) -> Option<f32> {
        match param {
            "delay_time" => Some((self.delay_samples as f32 / self.sample_rate) * 1000.0),
            "feedback" => Some(self.feedback),
            "mix" => Some(self.mix),
            _ => None,
        }
    }
}

// Simple reverb (using multiple delays)
pub struct Reverb {
    delays: Vec<Delay>,
    room_size: f32,
    damping: f32,
    mix: f32,
}

impl Reverb {
    pub fn new(sample_rate: f32) -> Self {
        // Create multiple delay lines for reverb
        let delay_times = vec![37.0, 43.0, 67.0, 73.0, 101.0, 107.0]; // Prime numbers
        let mut delays = Vec::new();
        
        for time in delay_times {
            let mut delay = Delay::new(sample_rate);
            delay.set_delay_time(time);
            delay.feedback = 0.5;
            delays.push(delay);
        }
        
        Self {
            delays,
            room_size: 0.5,
            damping: 0.5,
            mix: 0.3,
        }
    }
}

impl AudioEffect for Reverb {
    fn process(&mut self, input: &[f32], output: &mut [f32]) {
        output.copy_from_slice(input);
        
        let mut temp_buffer = vec![0.0; input.len()];
        let mut accumulator = vec![0.0; input.len()];
        
        // Process through each delay line
        let delays_count = self.delays.len() as f32;
        for delay in &mut self.delays {
            delay.process(input, &mut temp_buffer);
            
            // Accumulate delayed signals
            for (i, &sample) in temp_buffer.iter().enumerate() {
                accumulator[i] += sample * (1.0 / delays_count);
            }
        }
        
        // Apply damping and mix
        for (i, &dry) in input.iter().enumerate() {
            let wet = accumulator[i] * (1.0 - self.damping);
            output[i] = dry * (1.0 - self.mix) + wet * self.mix;
        }
    }
    
    fn reset(&mut self) {
        for delay in &mut self.delays {
            delay.reset();
        }
    }
    
    fn set_parameter(&mut self, param: &str, value: f32) {
        match param {
            "room_size" => {
                self.room_size = value.clamp(0.0, 1.0);
                // Adjust delay feedback based on room size
                for delay in &mut self.delays {
                    delay.feedback = 0.3 + self.room_size * 0.4;
                }
            }
            "damping" => self.damping = value.clamp(0.0, 1.0),
            "mix" => self.mix = value.clamp(0.0, 1.0),
            _ => {}
        }
    }
    
    fn get_parameter(&self, param: &str) -> Option<f32> {
        match param {
            "room_size" => Some(self.room_size),
            "damping" => Some(self.damping),
            "mix" => Some(self.mix),
            _ => None,
        }
    }
}

// Simple compressor
pub struct Compressor {
    threshold: f32,
    ratio: f32,
    attack: f32,
    release: f32,
    makeup_gain: f32,
    envelope: f32,
    sample_rate: f32,
}

impl Compressor {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            threshold: -12.0, // dB
            ratio: 4.0,
            attack: 0.005, // 5ms
            release: 0.1,  // 100ms
            makeup_gain: 0.0, // dB
            envelope: 0.0,
            sample_rate,
        }
    }
    
    fn db_to_linear(db: f32) -> f32 {
        10.0_f32.powf(db / 20.0)
    }
    
    fn linear_to_db(linear: f32) -> f32 {
        20.0 * linear.abs().log10()
    }
}

impl AudioEffect for Compressor {
    fn process(&mut self, input: &[f32], output: &mut [f32]) {
        let threshold_linear = Self::db_to_linear(self.threshold);
        let makeup_linear = Self::db_to_linear(self.makeup_gain);
        
        let attack_coeff = (-1.0 / (self.attack * self.sample_rate)).exp();
        let release_coeff = (-1.0 / (self.release * self.sample_rate)).exp();
        
        for (i, &sample) in input.iter().enumerate() {
            let input_level = sample.abs();
            
            // Update envelope
            let target = if input_level > self.envelope {
                input_level
            } else {
                input_level
            };
            
            let rate = if target > self.envelope {
                attack_coeff
            } else {
                release_coeff
            };
            
            self.envelope = target + (self.envelope - target) * rate;
            
            // Calculate gain reduction
            let mut gain = 1.0;
            if self.envelope > threshold_linear {
                let excess_db = Self::linear_to_db(self.envelope) - self.threshold;
                let compressed_db = excess_db / self.ratio;
                let gain_reduction_db = excess_db - compressed_db;
                gain = Self::db_to_linear(-gain_reduction_db);
            }
            
            // Apply compression and makeup gain
            output[i] = sample * gain * makeup_linear;
        }
    }
    
    fn reset(&mut self) {
        self.envelope = 0.0;
    }
    
    fn set_parameter(&mut self, param: &str, value: f32) {
        match param {
            "threshold" => self.threshold = value.clamp(-60.0, 0.0),
            "ratio" => self.ratio = value.clamp(1.0, 20.0),
            "attack" => self.attack = value.clamp(0.0001, 0.1),
            "release" => self.release = value.clamp(0.01, 2.0),
            "makeup_gain" => self.makeup_gain = value.clamp(-12.0, 24.0),
            _ => {}
        }
    }
    
    fn get_parameter(&self, param: &str) -> Option<f32> {
        match param {
            "threshold" => Some(self.threshold),
            "ratio" => Some(self.ratio),
            "attack" => Some(self.attack),
            "release" => Some(self.release),
            "makeup_gain" => Some(self.makeup_gain),
            _ => None,
        }
    }
}

// Biquad filter for EQ
pub struct BiquadFilter {
    b0: f32, b1: f32, b2: f32,
    a1: f32, a2: f32,
    x1: f32, x2: f32,
    y1: f32, y2: f32,
    sample_rate: f32,
    frequency: f32,
    q: f32,
    gain: f32,
    filter_type: FilterType,
}

#[derive(Clone, Copy)]
pub enum FilterType {
    LowPass,
    HighPass,
    BandPass,
    Notch,
    Peak,
    LowShelf,
    HighShelf,
}

impl BiquadFilter {
    pub fn new(sample_rate: f32, filter_type: FilterType) -> Self {
        let mut filter = Self {
            b0: 1.0, b1: 0.0, b2: 0.0,
            a1: 0.0, a2: 0.0,
            x1: 0.0, x2: 0.0,
            y1: 0.0, y2: 0.0,
            sample_rate,
            frequency: 1000.0,
            q: 0.707,
            gain: 0.0,
            filter_type,
        };
        filter.update_coefficients();
        filter
    }
    
    fn update_coefficients(&mut self) {
        let w = 2.0 * std::f32::consts::PI * self.frequency / self.sample_rate;
        let cos_w = w.cos();
        let sin_w = w.sin();
        let alpha = sin_w / (2.0 * self.q);
        let a = 10.0_f32.powf(self.gain / 40.0);
        
        match self.filter_type {
            FilterType::LowPass => {
                let b0 = (1.0 - cos_w) / 2.0;
                let b1 = 1.0 - cos_w;
                let b2 = (1.0 - cos_w) / 2.0;
                let a0 = 1.0 + alpha;
                let a1 = -2.0 * cos_w;
                let a2 = 1.0 - alpha;
                
                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
            FilterType::HighPass => {
                let b0 = (1.0 + cos_w) / 2.0;
                let b1 = -(1.0 + cos_w);
                let b2 = (1.0 + cos_w) / 2.0;
                let a0 = 1.0 + alpha;
                let a1 = -2.0 * cos_w;
                let a2 = 1.0 - alpha;
                
                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
            FilterType::Peak => {
                let b0 = 1.0 + alpha * a;
                let b1 = -2.0 * cos_w;
                let b2 = 1.0 - alpha * a;
                let a0 = 1.0 + alpha / a;
                let a1 = -2.0 * cos_w;
                let a2 = 1.0 - alpha / a;
                
                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
            _ => {
                // Default to pass-through
                self.b0 = 1.0;
                self.b1 = 0.0;
                self.b2 = 0.0;
                self.a1 = 0.0;
                self.a2 = 0.0;
            }
        }
    }
    
    pub fn process_sample(&mut self, input: f32) -> f32 {
        let output = self.b0 * input + self.b1 * self.x1 + self.b2 * self.x2
                    - self.a1 * self.y1 - self.a2 * self.y2;
        
        self.x2 = self.x1;
        self.x1 = input;
        self.y2 = self.y1;
        self.y1 = output;
        
        output
    }
}

impl AudioEffect for BiquadFilter {
    fn process(&mut self, input: &[f32], output: &mut [f32]) {
        for (i, &sample) in input.iter().enumerate() {
            output[i] = self.process_sample(sample);
        }
    }
    
    fn reset(&mut self) {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;
    }
    
    fn set_parameter(&mut self, param: &str, value: f32) {
        match param {
            "frequency" => {
                self.frequency = value.clamp(20.0, 20000.0);
                self.update_coefficients();
            }
            "q" => {
                self.q = value.clamp(0.1, 10.0);
                self.update_coefficients();
            }
            "gain" => {
                self.gain = value.clamp(-24.0, 24.0);
                self.update_coefficients();
            }
            _ => {}
        }
    }
    
    fn get_parameter(&self, param: &str) -> Option<f32> {
        match param {
            "frequency" => Some(self.frequency),
            "q" => Some(self.q),
            "gain" => Some(self.gain),
            _ => None,
        }
    }
}