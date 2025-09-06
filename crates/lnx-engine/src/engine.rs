use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::Instant;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{Sender, Receiver};
use ringbuf::{HeapRb, traits::Split};

use crate::graph::AudioGraph;
use crate::devices::DeviceManager;
use crate::latency::{LatencyMeter, LatencyStats};
use crate::beatmachine::BeatMachine;

pub struct AudioEngine {
    // Core components
    graph: Arc<Mutex<AudioGraph>>,
    device_manager: Arc<DeviceManager>,
    latency_meter: Arc<LatencyMeter>,
    beatmachine: Arc<Mutex<BeatMachine>>,
    
    // Stream handling
    input_stream: Option<cpal::Stream>,
    output_stream: Option<cpal::Stream>,
    
    // Configuration
    sample_rate: AtomicU32,
    buffer_size: AtomicU32,
    
    // State
    is_running: AtomicBool,
    
    // Inter-thread communication
    control_sender: Sender<ControlMessage>,
    control_receiver: Receiver<ControlMessage>,
    
    // Audio buffers (lock-free ring buffers)
    input_producer: Option<ringbuf::HeapProd<f32>>,
    input_consumer: Option<ringbuf::HeapCons<f32>>,
    output_producer: Option<ringbuf::HeapProd<f32>>,
    output_consumer: Option<ringbuf::HeapCons<f32>>,
}

#[derive(Debug, Clone)]
pub enum ControlMessage {
    Start,
    Stop,
    UpdateSampleRate(u32),
    UpdateBufferSize(u32),
    SelectInputDevice(String),
    SelectOutputDevice(String),
}

impl AudioEngine {
    pub fn new() -> Self {
        let (control_sender, control_receiver) = crossbeam_channel::unbounded();
        
        // Create ring buffers for audio data
        let input_rb = HeapRb::<f32>::new(8192);
        let (input_producer, input_consumer) = input_rb.split();
        let output_rb = HeapRb::<f32>::new(8192);
        let (output_producer, output_consumer) = output_rb.split();
        
        Self {
            graph: Arc::new(Mutex::new(AudioGraph::new())),
            device_manager: Arc::new(DeviceManager::new()),
            latency_meter: Arc::new(LatencyMeter::new(1000)), // Store up to 1000 measurements
            beatmachine: Arc::new(Mutex::new(BeatMachine::new())),
            input_stream: None,
            output_stream: None,
            sample_rate: AtomicU32::new(48000),
            buffer_size: AtomicU32::new(256),
            is_running: AtomicBool::new(false),
            control_sender,
            control_receiver,
            input_producer: Some(input_producer),
            input_consumer: Some(input_consumer),
            output_producer: Some(output_producer),
            output_consumer: Some(output_consumer),
        }
    }
    
    pub fn initialize(&mut self) -> Result<(), String> {
        // Initialize audio host
        let host = cpal::default_host();
        
        // Get default devices
        let input_device = host.default_input_device()
            .ok_or_else(|| "No input device available".to_string())?;
        let output_device = host.default_output_device()
            .ok_or_else(|| "No output device available".to_string())?;
        
        // Get device configs
        let _input_config = input_device.default_input_config()
            .map_err(|e| format!("Failed to get input config: {}", e))?;
        let output_config = output_device.default_output_config()
            .map_err(|e| format!("Failed to get output config: {}", e))?;
        
        // Update sample rate
        self.sample_rate.store(
            output_config.sample_rate().0,
            Ordering::Relaxed
        );
        
        log::info!("Audio Engine initialized");
        log::info!("  Input: {}", input_device.name().unwrap_or_default());
        log::info!("  Output: {}", output_device.name().unwrap_or_default());
        log::info!("  Sample Rate: {} Hz", self.sample_rate.load(Ordering::Relaxed));
        
        Ok(())
    }
    
    pub fn start(&mut self) -> Result<(), String> {
        if self.is_running.load(Ordering::Relaxed) {
            return Ok(());
        }
        
        // Create and start streams
        self.create_streams()?;
        
        self.is_running.store(true, Ordering::Relaxed);
        log::info!("Audio Engine started");
        
        Ok(())
    }
    
    pub fn stop(&mut self) -> Result<(), String> {
        if !self.is_running.load(Ordering::Relaxed) {
            return Ok(());
        }
        
        // Stop and drop streams
        self.input_stream = None;
        self.output_stream = None;
        
        self.is_running.store(false, Ordering::Relaxed);
        log::info!("Audio Engine stopped");
        
        Ok(())
    }
    
    fn create_streams(&mut self) -> Result<(), String> {
        let host = cpal::default_host();
        
        // Get devices
        let input_device = host.default_input_device()
            .ok_or_else(|| "No input device".to_string())?;
        let output_device = host.default_output_device()
            .ok_or_else(|| "No output device".to_string())?;
        
        // Get configs
        let _input_config = input_device.default_input_config()
            .map_err(|e| e.to_string())?;
        let output_config = output_device.default_output_config()
            .map_err(|e| e.to_string())?;
        
        // Clone for the closure
        let graph = Arc::clone(&self.graph);
        let latency_meter = Arc::clone(&self.latency_meter);
        let beatmachine = Arc::clone(&self.beatmachine);
        let buffer_size = self.buffer_size.load(Ordering::Relaxed) as usize;
        let sample_rate = self.sample_rate.load(Ordering::Relaxed) as usize;
        
        // Start latency measurement
        latency_meter.start_measurement(buffer_size, sample_rate);
        
        // Create output stream
        let output_stream = match output_config.sample_format() {
            cpal::SampleFormat::F32 => {
                output_device.build_output_stream(
                    &output_config.config(),
                    move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                        let process_start = Instant::now();
                        
                        // Clear output buffer
                        for sample in data.iter_mut() {
                            *sample = 0.0;
                        }
                        
                        
                        // Process beatmachine sequencer
                        if let Ok(bm) = beatmachine.try_lock() {
                            bm.process_sequencer();
                            // Process beatmachine audio and mix to output
                            bm.process_audio(data, 2); // Assuming stereo output
                        }
                        
                        // Process audio through the graph and add to existing output
                        if let Ok(mut g) = graph.try_lock() {
                            // Create temporary buffer for graph processing
                            let mut graph_output = vec![0.0f32; data.len()];
                            g.process_audio(&mut graph_output);
                            
                            // Mix graph output with beatmachine output
                            for (i, sample) in graph_output.iter().enumerate() {
                                if i < data.len() {
                                    data[i] += sample;
                                }
                            }
                        }
                        
                        // Measure processing latency
                        let process_duration = process_start.elapsed();
                        latency_meter.add_round_trip_measurement(process_duration);
                    },
                    |err| eprintln!("Audio output error: {}", err),
                    None
                ).map_err(|e| e.to_string())?
            }
            _ => return Err("Unsupported sample format".to_string()),
        };
        
        // Start the stream
        output_stream.play().map_err(|e| e.to_string())?;
        self.output_stream = Some(output_stream);
        
        // TODO: Create input stream similarly
        
        Ok(())
    }
    
    pub fn get_sample_rate(&self) -> u32 {
        self.sample_rate.load(Ordering::Relaxed)
    }
    
    pub fn get_buffer_size(&self) -> u32 {
        self.buffer_size.load(Ordering::Relaxed)
    }
    
    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::Relaxed)
    }
    
    pub fn process_control_messages(&mut self) {
        while let Ok(msg) = self.control_receiver.try_recv() {
            match msg {
                ControlMessage::Start => {
                    let _ = self.start();
                }
                ControlMessage::Stop => {
                    let _ = self.stop();
                }
                ControlMessage::UpdateSampleRate(rate) => {
                    self.sample_rate.store(rate, Ordering::Relaxed);
                }
                ControlMessage::UpdateBufferSize(size) => {
                    self.buffer_size.store(size, Ordering::Relaxed);
                }
                ControlMessage::SelectInputDevice(name) => {
                    // TODO: Implement device selection
                    log::info!("Selecting input device: {}", name);
                }
                ControlMessage::SelectOutputDevice(name) => {
                    // TODO: Implement device selection
                    log::info!("Selecting output device: {}", name);
                }
            }
        }
    }
    
    // Latency measurement methods
    pub fn get_latency_stats(&self) -> Option<LatencyStats> {
        self.latency_meter.get_stats()
    }
    
    pub fn get_latency_report(&self) -> String {
        self.latency_meter.get_report()
    }
    
    pub fn clear_latency_measurements(&self) {
        self.latency_meter.clear_measurements();
    }
    
    pub fn meets_latency_target(&self, target_ms: f64) -> Option<bool> {
        self.latency_meter.meets_latency_target(target_ms)
    }
    
    // Audio graph convenience methods
    pub fn add_file_player(&self, file_path: String, name: String) -> Result<crate::graph::NodeId, String> {
        if let Ok(mut graph) = self.graph.lock() {
            graph.add_file_player_node(file_path, name)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn play_file(&self, node_id: crate::graph::NodeId) -> Result<(), String> {
        if let Ok(graph) = self.graph.lock() {
            graph.play_file(node_id)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn stop_file(&self, node_id: crate::graph::NodeId) -> Result<(), String> {
        if let Ok(graph) = self.graph.lock() {
            graph.stop_file(node_id)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn pause_file(&self, node_id: crate::graph::NodeId) -> Result<(), String> {
        if let Ok(graph) = self.graph.lock() {
            graph.pause_file(node_id)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn resume_file(&self, node_id: crate::graph::NodeId) -> Result<(), String> {
        if let Ok(graph) = self.graph.lock() {
            graph.resume_file(node_id)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn set_file_gain(&self, node_id: crate::graph::NodeId, gain: f32) -> Result<(), String> {
        if let Ok(graph) = self.graph.lock() {
            graph.set_file_gain(node_id, gain)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn connect_file_to_output(&self, file_node_id: crate::graph::NodeId) -> Result<crate::graph::ConnectionId, String> {
        if let Ok(mut graph) = self.graph.lock() {
            // Find or create master output node
            let output_node_id = graph.add_node(crate::graph::NodeType::Output, "Master Output".to_string());
            
            // Connect left and right channels
            let left_conn = graph.connect_nodes(file_node_id, 0, output_node_id, 0)?;
            let _right_conn = graph.connect_nodes(file_node_id, 1, output_node_id, 1)?;
            
            Ok(left_conn)
        } else {
            Err("Could not acquire lock on audio graph".to_string())
        }
    }
    
    pub fn get_device_manager(&self) -> &Arc<DeviceManager> {
        &self.device_manager
    }
    
    // Beat machine methods
    pub fn trigger_pad(&self, pad_id: usize, velocity: f32) -> Result<(), String> {
        if let Ok(beatmachine) = self.beatmachine.lock() {
            beatmachine.trigger_pad(pad_id, velocity);
            Ok(())
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
    
    pub fn set_beatmachine_bpm(&self, bpm: f32) -> Result<(), String> {
        if let Ok(beatmachine) = self.beatmachine.lock() {
            beatmachine.set_bpm(bpm);
            Ok(())
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
    
    pub fn play_beatmachine(&self) -> Result<(), String> {
        if let Ok(beatmachine) = self.beatmachine.lock() {
            beatmachine.play();
            Ok(())
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
    
    pub fn stop_beatmachine(&self) -> Result<(), String> {
        if let Ok(beatmachine) = self.beatmachine.lock() {
            beatmachine.stop();
            Ok(())
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
    
    pub fn set_beatmachine_step(&self, step: usize, pad: usize, active: bool, velocity: f32) -> Result<(), String> {
        if let Ok(beatmachine) = self.beatmachine.lock() {
            beatmachine.set_step(step, pad, active, velocity);
            Ok(())
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
    
    pub fn load_pad_sample(&self, pad_id: usize, file_path: &str) -> Result<(), String> {
        use crate::audio_file::AudioFilePlayer;
        use std::sync::{Arc, Mutex};
        
        // Load the audio file
        let player = AudioFilePlayer::load_wav(file_path)?;
        let shared_player = Arc::new(Mutex::new(player));
        
        // Assign to pad
        if let Ok(mut beatmachine) = self.beatmachine.lock() {
            if pad_id < beatmachine.pads.len() {
                beatmachine.pads[pad_id].load_sample(shared_player);
                Ok(())
            } else {
                Err(format!("Invalid pad ID: {}", pad_id))
            }
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
    
    pub fn get_beatmachine_status(&self) -> Result<(bool, usize, f32), String> {
        if let Ok(beatmachine) = self.beatmachine.lock() {
            Ok((
                beatmachine.is_playing(),
                beatmachine.get_current_step(), 
                beatmachine.get_bpm()
            ))
        } else {
            Err("Could not acquire lock on beatmachine".to_string())
        }
    }
}