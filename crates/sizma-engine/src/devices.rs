use std::sync::{Arc, Mutex};
use cpal::traits::{DeviceTrait, HostTrait};

#[derive(Debug, Clone)]
pub struct AudioDevice {
    pub name: String,
    pub is_input: bool,
    pub is_output: bool,
    pub channels: usize,
    pub sample_rate: u32,
    pub is_default: bool,
}

pub struct DeviceManager {
    host: cpal::Host,
    input_devices: Vec<AudioDevice>,
    output_devices: Vec<AudioDevice>,
    current_input: Option<String>,
    current_output: Option<String>,
}

impl DeviceManager {
    pub fn new() -> Self {
        let host = cpal::default_host();
        let mut manager = Self {
            host,
            input_devices: Vec::new(),
            output_devices: Vec::new(),
            current_input: None,
            current_output: None,
        };
        
        manager.enumerate_devices();
        manager
    }
    
    pub fn enumerate_devices(&mut self) {
        self.input_devices.clear();
        self.output_devices.clear();
        
        // Get default devices
        let default_input = self.host.default_input_device()
            .and_then(|d| d.name().ok());
        let default_output = self.host.default_output_device()
            .and_then(|d| d.name().ok());
        
        // Enumerate input devices
        if let Ok(devices) = self.host.input_devices() {
            for device in devices {
                if let Ok(name) = device.name() {
                    if let Ok(config) = device.default_input_config() {
                        let audio_device = AudioDevice {
                            name: name.clone(),
                            is_input: true,
                            is_output: false,
                            channels: config.channels() as usize,
                            sample_rate: config.sample_rate().0,
                            is_default: Some(&name) == default_input.as_ref(),
                        };
                        
                        self.input_devices.push(audio_device);
                        
                        // Set as current if it's the default
                        if Some(&name) == default_input.as_ref() {
                            self.current_input = Some(name);
                        }
                    }
                }
            }
        }
        
        // Enumerate output devices
        if let Ok(devices) = self.host.output_devices() {
            for device in devices {
                if let Ok(name) = device.name() {
                    if let Ok(config) = device.default_output_config() {
                        let audio_device = AudioDevice {
                            name: name.clone(),
                            is_input: false,
                            is_output: true,
                            channels: config.channels() as usize,
                            sample_rate: config.sample_rate().0,
                            is_default: Some(&name) == default_output.as_ref(),
                        };
                        
                        self.output_devices.push(audio_device);
                        
                        // Set as current if it's the default
                        if Some(&name) == default_output.as_ref() {
                            self.current_output = Some(name);
                        }
                    }
                }
            }
        }
        
        log::info!("Found {} input devices, {} output devices", 
                   self.input_devices.len(), self.output_devices.len());
    }
    
    pub fn get_input_devices(&self) -> Vec<AudioDevice> {
        self.input_devices.clone()
    }
    
    pub fn get_output_devices(&self) -> Vec<AudioDevice> {
        self.output_devices.clone()
    }
    
    pub fn get_current_input(&self) -> Option<String> {
        self.current_input.clone()
    }
    
    pub fn get_current_output(&self) -> Option<String> {
        self.current_output.clone()
    }
    
    pub fn set_input_device(&mut self, name: &str) -> Result<(), String> {
        if self.input_devices.iter().any(|d| d.name == name) {
            self.current_input = Some(name.to_string());
            log::info!("Set input device to: {}", name);
            Ok(())
        } else {
            Err(format!("Input device '{}' not found", name))
        }
    }
    
    pub fn set_output_device(&mut self, name: &str) -> Result<(), String> {
        if self.output_devices.iter().any(|d| d.name == name) {
            self.current_output = Some(name.to_string());
            log::info!("Set output device to: {}", name);
            Ok(())
        } else {
            Err(format!("Output device '{}' not found", name))
        }
    }
    
    pub fn get_device_by_name(&self, name: &str, is_input: bool) -> Option<cpal::Device> {
        let devices = if is_input {
            self.host.input_devices().ok()?
        } else {
            self.host.output_devices().ok()?
        };
        
        for device in devices {
            if let Ok(device_name) = device.name() {
                if device_name == name {
                    return Some(device);
                }
            }
        }
        
        None
    }
    
    pub fn get_default_input_device(&self) -> Option<cpal::Device> {
        self.host.default_input_device()
    }
    
    pub fn get_default_output_device(&self) -> Option<cpal::Device> {
        self.host.default_output_device()
    }
    
    pub fn refresh(&mut self) {
        self.enumerate_devices();
    }
}