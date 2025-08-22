use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_float, c_int, c_uint};
use std::sync::{Arc, Mutex};

use crate::engine::AudioEngine;

// Opaque handle for the audio engine
pub struct LNXAudioEngine {
    engine: Arc<Mutex<AudioEngine>>,
}

// Node types for FFI
#[repr(C)]
pub enum LNXNodeType {
    Input = 0,
    Output = 1,
    Mixer = 2,
    Effect = 3,
    Generator = 4,
    Analyzer = 5,
}

// Device info structure for FFI
#[repr(C)]
pub struct LNXDeviceInfo {
    pub name: *const c_char,
    pub is_input: c_int,
    pub is_output: c_int,
    pub channels: c_uint,
    pub sample_rate: c_uint,
    pub is_default: c_int,
}

// Connection info for FFI
#[repr(C)]
pub struct LNXConnection {
    pub id: c_uint,
    pub source_node: c_uint,
    pub source_channel: c_uint,
    pub dest_node: c_uint,
    pub dest_channel: c_uint,
    pub gain: c_float,
    pub enabled: c_int,
}

// Create and destroy engine
#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_create() -> *mut LNXAudioEngine {
    let engine = AudioEngine::new();
    let boxed = Box::new(LNXAudioEngine {
        engine: Arc::new(Mutex::new(engine)),
    });
    Box::into_raw(boxed)
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_destroy(engine: *mut LNXAudioEngine) {
    if !engine.is_null() {
        unsafe {
            let _ = Box::from_raw(engine);
        }
    }
}

// Initialize and control
#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_initialize(engine: *mut LNXAudioEngine) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(mut eng) = engine.engine.lock() {
            match eng.initialize() {
                Ok(()) => 0,
                Err(_) => -1,
            }
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_start(engine: *mut LNXAudioEngine) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(mut eng) = engine.engine.lock() {
            match eng.start() {
                Ok(()) => 0,
                Err(_) => -1,
            }
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_stop(engine: *mut LNXAudioEngine) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(mut eng) = engine.engine.lock() {
            match eng.stop() {
                Ok(()) => 0,
                Err(_) => -1,
            }
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_is_running(engine: *mut LNXAudioEngine) -> c_int {
    if engine.is_null() {
        return 0;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(eng) = engine.engine.lock() {
            if eng.is_running() { 1 } else { 0 }
        } else {
            0
        }
    }
}

// Configuration
#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_get_sample_rate(engine: *mut LNXAudioEngine) -> c_uint {
    if engine.is_null() {
        return 0;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(eng) = engine.engine.lock() {
            eng.get_sample_rate()
        } else {
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_get_buffer_size(engine: *mut LNXAudioEngine) -> c_uint {
    if engine.is_null() {
        return 0;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(eng) = engine.engine.lock() {
            eng.get_buffer_size()
        } else {
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_set_buffer_size(engine: *mut LNXAudioEngine, size: c_uint) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(eng) = engine.engine.lock() {
            // Send control message to update buffer size
            // Note: This would need to be implemented in the engine
            0
        } else {
            -1
        }
    }
}

// Graph operations
#[unsafe(no_mangle)]
pub extern "C" fn lnx_graph_add_node(
    engine: *mut LNXAudioEngine,
    node_type: LNXNodeType,
    name: *const c_char,
) -> c_uint {
    if engine.is_null() || name.is_null() {
        return 0;
    }
    
    unsafe {
        let engine = &*engine;
        let _name_str = CStr::from_ptr(name).to_string_lossy().into_owned();
        
        if let Ok(_eng) = engine.engine.lock() {
            // This would need to access the graph through the engine
            // For now, return a placeholder
            1
        } else {
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_graph_remove_node(engine: *mut LNXAudioEngine, node_id: c_uint) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(_eng) = engine.engine.lock() {
            // Would remove node from graph
            0
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_graph_connect_nodes(
    engine: *mut LNXAudioEngine,
    _source_node: c_uint,
    _source_channel: c_uint,
    _dest_node: c_uint,
    _dest_channel: c_uint,
) -> c_uint {
    if engine.is_null() {
        return 0;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(_eng) = engine.engine.lock() {
            // Would create connection in graph
            1
        } else {
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_graph_disconnect(engine: *mut LNXAudioEngine, _connection_id: c_uint) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(_eng) = engine.engine.lock() {
            // Would remove connection from graph
            0
        } else {
            -1
        }
    }
}

// Node control
#[unsafe(no_mangle)]
pub extern "C" fn lnx_node_set_gain(
    engine: *mut LNXAudioEngine,
    _node_id: c_uint,
    _gain: c_float,
) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(_eng) = engine.engine.lock() {
            // Would set node gain in graph
            0
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_node_set_pan(
    engine: *mut LNXAudioEngine,
    _node_id: c_uint,
    _pan: c_float,
) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(_eng) = engine.engine.lock() {
            // Would set node pan in graph
            0
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_node_set_enabled(
    engine: *mut LNXAudioEngine,
    _node_id: c_uint,
    _enabled: c_int,
) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(_eng) = engine.engine.lock() {
            // Would set node enabled state in graph
            0
        } else {
            -1
        }
    }
}

// Effect parameters
#[unsafe(no_mangle)]
pub extern "C" fn lnx_effect_set_parameter(
    engine: *mut LNXAudioEngine,
    _node_id: c_uint,
    param_name: *const c_char,
    _value: c_float,
) -> c_int {
    if engine.is_null() || param_name.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        let _param_str = CStr::from_ptr(param_name).to_string_lossy().into_owned();
        
        if let Ok(_eng) = engine.engine.lock() {
            // Would set effect parameter
            0
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_effect_get_parameter(
    engine: *mut LNXAudioEngine,
    _node_id: c_uint,
    param_name: *const c_char,
    value: *mut c_float,
) -> c_int {
    if engine.is_null() || param_name.is_null() || value.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        let _param_str = CStr::from_ptr(param_name).to_string_lossy().into_owned();
        
        if let Ok(_eng) = engine.engine.lock() {
            // Would get effect parameter
            *value = 0.0;
            0
        } else {
            -1
        }
    }
}

// Device management
#[unsafe(no_mangle)]
pub extern "C" fn lnx_device_select_input(
    engine: *mut LNXAudioEngine,
    device_name: *const c_char,
) -> c_int {
    if engine.is_null() || device_name.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        let _name_str = CStr::from_ptr(device_name).to_string_lossy().into_owned();
        
        if let Ok(_eng) = engine.engine.lock() {
            // Would select input device
            0
        } else {
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lnx_device_select_output(
    engine: *mut LNXAudioEngine,
    device_name: *const c_char,
) -> c_int {
    if engine.is_null() || device_name.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        let _name_str = CStr::from_ptr(device_name).to_string_lossy().into_owned();
        
        if let Ok(_eng) = engine.engine.lock() {
            // Would select output device
            0
        } else {
            -1
        }
    }
}

// Utility functions
#[unsafe(no_mangle)]
pub extern "C" fn lnx_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// Process control messages (for async operations)
#[unsafe(no_mangle)]
pub extern "C" fn lnx_engine_process_messages(engine: *mut LNXAudioEngine) -> c_int {
    if engine.is_null() {
        return -1;
    }
    
    unsafe {
        let engine = &*engine;
        if let Ok(mut eng) = engine.engine.lock() {
            eng.process_control_messages();
            0
        } else {
            -1
        }
    }
}