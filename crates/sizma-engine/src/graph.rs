use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU32, Ordering};

pub type NodeId = u32;
pub type ConnectionId = u32;

#[derive(Debug, Clone)]
pub enum NodeType {
    Input,
    Output,
    Mixer,
    Effect(String),
    Generator,
    Analyzer,
}

#[derive(Debug, Clone)]
pub struct AudioNode {
    pub id: NodeId,
    pub name: String,
    pub node_type: NodeType,
    pub input_channels: usize,
    pub output_channels: usize,
    pub enabled: bool,
    pub gain: f32,
    pub pan: f32,  // -1.0 (left) to 1.0 (right)
}

#[derive(Debug, Clone)]
pub struct Connection {
    pub id: ConnectionId,
    pub source_node: NodeId,
    pub source_channel: usize,
    pub dest_node: NodeId,
    pub dest_channel: usize,
    pub gain: f32,
    pub enabled: bool,
}

pub struct AudioGraph {
    nodes: HashMap<NodeId, AudioNode>,
    connections: Vec<Connection>,
    processing_order: Vec<NodeId>,
    next_node_id: AtomicU32,
    next_connection_id: AtomicU32,
    
    // Audio buffers for processing
    node_buffers: HashMap<NodeId, Vec<Vec<f32>>>,
    buffer_size: usize,
}

impl AudioGraph {
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            connections: Vec::new(),
            processing_order: Vec::new(),
            next_node_id: AtomicU32::new(1),
            next_connection_id: AtomicU32::new(1),
            node_buffers: HashMap::new(),
            buffer_size: 256,
        }
    }
    
    pub fn add_node(&mut self, node_type: NodeType, name: String) -> NodeId {
        let id = self.next_node_id.fetch_add(1, Ordering::Relaxed);
        
        let (input_channels, output_channels) = match &node_type {
            NodeType::Input => (0, 2),
            NodeType::Output => (2, 0),
            NodeType::Mixer => (8, 2),
            NodeType::Effect(_) => (2, 2),
            NodeType::Generator => (0, 2),
            NodeType::Analyzer => (2, 0),
        };
        
        let node = AudioNode {
            id,
            name,
            node_type,
            input_channels,
            output_channels,
            enabled: true,
            gain: 1.0,
            pan: 0.0,
        };
        
        self.nodes.insert(id, node);
        
        // Allocate buffers for this node
        let buffers = vec![vec![0.0; self.buffer_size]; output_channels];
        self.node_buffers.insert(id, buffers);
        
        // Update processing order
        self.update_processing_order();
        
        id
    }
    
    pub fn remove_node(&mut self, node_id: NodeId) -> Result<(), String> {
        if !self.nodes.contains_key(&node_id) {
            return Err(format!("Node {} not found", node_id));
        }
        
        // Remove all connections involving this node
        self.connections.retain(|conn| {
            conn.source_node != node_id && conn.dest_node != node_id
        });
        
        // Remove the node
        self.nodes.remove(&node_id);
        self.node_buffers.remove(&node_id);
        
        // Update processing order
        self.update_processing_order();
        
        Ok(())
    }
    
    pub fn connect_nodes(
        &mut self,
        source_node: NodeId,
        source_channel: usize,
        dest_node: NodeId,
        dest_channel: usize,
    ) -> Result<ConnectionId, String> {
        // Validate nodes exist
        let source = self.nodes.get(&source_node)
            .ok_or_else(|| format!("Source node {} not found", source_node))?;
        let dest = self.nodes.get(&dest_node)
            .ok_or_else(|| format!("Destination node {} not found", dest_node))?;
        
        // Validate channels
        if source_channel >= source.output_channels {
            return Err(format!("Invalid source channel {}", source_channel));
        }
        if dest_channel >= dest.input_channels {
            return Err(format!("Invalid destination channel {}", dest_channel));
        }
        
        // Check for cycles
        if self.would_create_cycle(source_node, dest_node) {
            return Err("Connection would create a cycle".to_string());
        }
        
        let id = self.next_connection_id.fetch_add(1, Ordering::Relaxed);
        
        let connection = Connection {
            id,
            source_node,
            source_channel,
            dest_node,
            dest_channel,
            gain: 1.0,
            enabled: true,
        };
        
        self.connections.push(connection);
        
        // Update processing order
        self.update_processing_order();
        
        Ok(id)
    }
    
    pub fn disconnect(&mut self, connection_id: ConnectionId) -> Result<(), String> {
        let index = self.connections.iter()
            .position(|c| c.id == connection_id)
            .ok_or_else(|| format!("Connection {} not found", connection_id))?;
        
        self.connections.remove(index);
        
        // Update processing order
        self.update_processing_order();
        
        Ok(())
    }
    
    pub fn process_audio(&mut self, output_buffer: &mut [f32]) {
        // Clear all node buffers
        for buffers in self.node_buffers.values_mut() {
            for buffer in buffers.iter_mut() {
                buffer.fill(0.0);
            }
        }
        
        // Process nodes in topological order
        let processing_order = self.processing_order.clone();
        for node_id in processing_order {
            self.process_node(node_id);
        }
        
        // Copy master output to the output buffer
        if let Some(master_output_node) = self.find_master_output() {
            if let Some(buffers) = self.node_buffers.get(&master_output_node) {
                // Mix stereo to output buffer (interleaved)
                let chunk_size = output_buffer.len() / 2;
                for i in 0..chunk_size.min(self.buffer_size) {
                    if buffers.len() >= 2 {
                        output_buffer[i * 2] = buffers[0][i];
                        output_buffer[i * 2 + 1] = buffers[1][i];
                    }
                }
            }
        } else {
            // No output node, fill with silence
            output_buffer.fill(0.0);
        }
    }
    
    fn process_node(&mut self, node_id: NodeId) {
        let node = match self.nodes.get(&node_id) {
            Some(n) if n.enabled => n.clone(),
            _ => return,
        };
        
        // Get input connections for this node
        let input_connections: Vec<Connection> = self.connections.iter()
            .filter(|c| c.dest_node == node_id && c.enabled)
            .cloned()
            .collect();
        
        // Mix inputs into node's input buffer
        if !input_connections.is_empty() {
            // Collect source data first to avoid borrow conflicts
            let mut source_data: Vec<(usize, Vec<f32>)> = Vec::new();
            for conn in &input_connections {
                if let Some(source_buffers) = self.node_buffers.get(&conn.source_node) {
                    if conn.source_channel < source_buffers.len() {
                        let data = source_buffers[conn.source_channel].clone();
                        source_data.push((conn.dest_channel, data.iter().map(|&s| s * conn.gain).collect()));
                    }
                }
            }
            
            // Now apply the collected data to destination
            if let Some(dest_buffers) = self.node_buffers.get_mut(&node_id) {
                for (dest_channel, data) in source_data {
                    if dest_channel < dest_buffers.len() {
                        for (i, &sample) in data.iter().enumerate().take(self.buffer_size) {
                            dest_buffers[dest_channel][i] += sample;
                        }
                    }
                }
            }
        }
        
        // Process the node based on its type
        match &node.node_type {
            NodeType::Input => {
                // Input nodes generate or receive external audio
                // For now, generate silence (would be replaced with actual input)
            }
            NodeType::Mixer => {
                // Apply gain and pan
                if let Some(buffers) = self.node_buffers.get_mut(&node_id) {
                    for buffer in buffers.iter_mut() {
                        for sample in buffer.iter_mut() {
                            *sample *= node.gain;
                        }
                    }
                }
            }
            NodeType::Effect(effect_type) => {
                // Process effect (placeholder for actual DSP)
                self.process_effect(&node, effect_type);
            }
            _ => {}
        }
    }
    
    fn process_effect(&mut self, _node: &AudioNode, effect_type: &str) {
        // Placeholder for effect processing
        // In a real implementation, this would dispatch to actual DSP code
        match effect_type {
            "reverb" => {
                // Apply reverb algorithm
            }
            "delay" => {
                // Apply delay algorithm
            }
            "eq" => {
                // Apply EQ algorithm
            }
            _ => {}
        }
    }
    
    fn would_create_cycle(&self, source: NodeId, dest: NodeId) -> bool {
        // Simple cycle detection using DFS
        let mut visited = HashMap::new();
        self.has_path_dfs(dest, source, &mut visited)
    }
    
    fn has_path_dfs(&self, from: NodeId, to: NodeId, visited: &mut HashMap<NodeId, bool>) -> bool {
        if from == to {
            return true;
        }
        
        if let Some(&already_visited) = visited.get(&from) {
            return already_visited;
        }
        
        visited.insert(from, false);
        
        for conn in &self.connections {
            if conn.source_node == from && conn.enabled {
                if self.has_path_dfs(conn.dest_node, to, visited) {
                    visited.insert(from, true);
                    return true;
                }
            }
        }
        
        false
    }
    
    fn update_processing_order(&mut self) {
        // Topological sort for processing order
        let mut in_degree: HashMap<NodeId, usize> = HashMap::new();
        let mut queue = Vec::new();
        let mut order = Vec::new();
        
        // Initialize in-degrees
        for &node_id in self.nodes.keys() {
            in_degree.insert(node_id, 0);
        }
        
        // Calculate in-degrees
        for conn in &self.connections {
            if conn.enabled {
                *in_degree.entry(conn.dest_node).or_insert(0) += 1;
            }
        }
        
        // Find nodes with no inputs
        for (&node_id, &degree) in &in_degree {
            if degree == 0 {
                queue.push(node_id);
            }
        }
        
        // Process queue
        while let Some(node_id) = queue.pop() {
            order.push(node_id);
            
            // Reduce in-degree for connected nodes
            for conn in &self.connections {
                if conn.source_node == node_id && conn.enabled {
                    if let Some(degree) = in_degree.get_mut(&conn.dest_node) {
                        *degree -= 1;
                        if *degree == 0 {
                            queue.push(conn.dest_node);
                        }
                    }
                }
            }
        }
        
        self.processing_order = order;
    }
    
    fn find_master_output(&self) -> Option<NodeId> {
        // Find the first enabled output node
        self.nodes.iter()
            .find(|(_, node)| matches!(node.node_type, NodeType::Output) && node.enabled)
            .map(|(&id, _)| id)
    }
    
    pub fn set_buffer_size(&mut self, size: usize) {
        self.buffer_size = size;
        
        // Reallocate all buffers
        for (node_id, node) in &self.nodes {
            let buffers = vec![vec![0.0; size]; node.output_channels];
            self.node_buffers.insert(*node_id, buffers);
        }
    }
    
    pub fn get_nodes(&self) -> Vec<AudioNode> {
        self.nodes.values().cloned().collect()
    }
    
    pub fn get_connections(&self) -> Vec<Connection> {
        self.connections.clone()
    }
    
    pub fn set_node_gain(&mut self, node_id: NodeId, gain: f32) {
        if let Some(node) = self.nodes.get_mut(&node_id) {
            node.gain = gain.clamp(0.0, 2.0);
        }
    }
    
    pub fn set_node_pan(&mut self, node_id: NodeId, pan: f32) {
        if let Some(node) = self.nodes.get_mut(&node_id) {
            node.pan = pan.clamp(-1.0, 1.0);
        }
    }
    
    pub fn set_node_enabled(&mut self, node_id: NodeId, enabled: bool) {
        if let Some(node) = self.nodes.get_mut(&node_id) {
            node.enabled = enabled;
        }
    }
}