use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{Sender, Receiver};
use ringbuf::{HeapRb, traits::{Consumer, Producer, Split}};

use crate::graph::AudioGraph;
use crate::devices::DeviceManager;

pub struct AudioEngine {
    // Core components
    graph: Arc<Mutex<AudioGraph>>,
    device_manager: Arc<DeviceManager>,
    
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
        let input_config = input_device.default_input_config()
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
        let input_config = input_device.default_input_config()
            .map_err(|e| e.to_string())?;
        let output_config = output_device.default_output_config()
            .map_err(|e| e.to_string())?;
        
        // Clone for the closure
        let graph = Arc::clone(&self.graph);
        let buffer_size = self.buffer_size.load(Ordering::Relaxed) as usize;
        
        // Create output stream
        let output_stream = match output_config.sample_format() {
            cpal::SampleFormat::F32 => {
                output_device.build_output_stream(
                    &output_config.config(),
                    move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                        // Process audio through the graph
                        if let Ok(mut g) = graph.try_lock() {
                            g.process_audio(data);
                        } else {
                            // If we can't get the lock, output silence
                            for sample in data.iter_mut() {
                                *sample = 0.0;
                            }
                        }
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
}