use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::collections::VecDeque;

#[derive(Debug, Clone)]
pub struct LatencyMeasurement {
    pub round_trip_ms: f64,
    pub input_to_output_ms: f64,
    pub buffer_latency_ms: f64,
    pub system_latency_ms: f64,
    pub timestamp: Instant,
}

#[derive(Debug, Clone)]
pub struct LatencyStats {
    pub min_ms: f64,
    pub max_ms: f64,
    pub avg_ms: f64,
    pub p99_ms: f64,
    pub p95_ms: f64,
    pub p50_ms: f64,
    pub samples: usize,
    pub last_update: Instant,
}

pub struct LatencyMeter {
    measurements: Arc<Mutex<VecDeque<LatencyMeasurement>>>,
    is_measuring: AtomicBool,
    test_start_time: AtomicU64,
    buffer_size: AtomicUsize,
    sample_rate: AtomicUsize,
    max_measurements: usize,
    
    // For round-trip latency testing
    test_signal_id: AtomicU64,
    test_signal_sent_time: AtomicU64,
}

impl LatencyMeter {
    pub fn new(max_measurements: usize) -> Self {
        Self {
            measurements: Arc::new(Mutex::new(VecDeque::with_capacity(max_measurements))),
            is_measuring: AtomicBool::new(false),
            test_start_time: AtomicU64::new(0),
            buffer_size: AtomicUsize::new(256),
            sample_rate: AtomicUsize::new(48000),
            max_measurements,
            test_signal_id: AtomicU64::new(0),
            test_signal_sent_time: AtomicU64::new(0),
        }
    }
    
    pub fn start_measurement(&self, buffer_size: usize, sample_rate: usize) {
        self.buffer_size.store(buffer_size, Ordering::Relaxed);
        self.sample_rate.store(sample_rate, Ordering::Relaxed);
        self.is_measuring.store(true, Ordering::Relaxed);
        self.test_start_time.store(
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos() as u64,
            Ordering::Relaxed
        );
        
        log::info!("Started latency measurement");
        log::info!("  Buffer size: {} samples", buffer_size);
        log::info!("  Sample rate: {} Hz", sample_rate);
        log::info!("  Buffer latency: {:.2} ms", 
                  (buffer_size as f64 / sample_rate as f64) * 1000.0);
    }
    
    pub fn stop_measurement(&self) {
        self.is_measuring.store(false, Ordering::Relaxed);
        log::info!("Stopped latency measurement");
    }
    
    pub fn is_measuring(&self) -> bool {
        self.is_measuring.load(Ordering::Relaxed)
    }
    
    /// Calculate theoretical buffer latency based on current settings
    pub fn calculate_buffer_latency_ms(&self) -> f64 {
        let buffer_size = self.buffer_size.load(Ordering::Relaxed) as f64;
        let sample_rate = self.sample_rate.load(Ordering::Relaxed) as f64;
        (buffer_size / sample_rate) * 1000.0
    }
    
    /// Measure round-trip latency by injecting a test signal
    pub fn inject_test_signal(&self) -> u64 {
        if !self.is_measuring() {
            return 0;
        }
        
        let signal_id = self.test_signal_id.fetch_add(1, Ordering::Relaxed) + 1;
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos() as u64;
        self.test_signal_sent_time.store(now, Ordering::Relaxed);
        
        log::debug!("Injected test signal ID: {}", signal_id);
        signal_id
    }
    
    /// Process a detected test signal and calculate latency
    pub fn process_detected_signal(&self, signal_id: u64) {
        if !self.is_measuring() {
            return;
        }
        
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos() as u64;
        let sent_time = self.test_signal_sent_time.load(Ordering::Relaxed);
        
        if sent_time == 0 {
            return;
        }
        
        let round_trip_ns = now.saturating_sub(sent_time);
        let round_trip_ms = round_trip_ns as f64 / 1_000_000.0;
        
        // Estimate input-to-output latency (assuming symmetric path)
        let input_to_output_ms = round_trip_ms / 2.0;
        
        let buffer_latency_ms = self.calculate_buffer_latency_ms();
        let system_latency_ms = input_to_output_ms - buffer_latency_ms;
        
        let measurement = LatencyMeasurement {
            round_trip_ms,
            input_to_output_ms,
            buffer_latency_ms,
            system_latency_ms: system_latency_ms.max(0.0),
            timestamp: Instant::now(),
        };
        
        self.add_measurement(measurement);
        
        log::debug!("Latency measurement: round-trip {:.2}ms, input-to-output {:.2}ms, buffer {:.2}ms, system {:.2}ms",
                   round_trip_ms, input_to_output_ms, buffer_latency_ms, system_latency_ms);
    }
    
    /// Add a manual latency measurement
    pub fn add_measurement(&self, measurement: LatencyMeasurement) {
        if let Ok(mut measurements) = self.measurements.lock() {
            if measurements.len() >= self.max_measurements {
                measurements.pop_front();
            }
            measurements.push_back(measurement);
        }
    }
    
    /// Add a simple round-trip measurement
    pub fn add_round_trip_measurement(&self, duration: Duration) {
        let round_trip_ms = duration.as_secs_f64() * 1000.0;
        let buffer_latency_ms = self.calculate_buffer_latency_ms();
        let input_to_output_ms = round_trip_ms / 2.0;
        let system_latency_ms = (input_to_output_ms - buffer_latency_ms).max(0.0);
        
        let measurement = LatencyMeasurement {
            round_trip_ms,
            input_to_output_ms,
            buffer_latency_ms,
            system_latency_ms,
            timestamp: Instant::now(),
        };
        
        self.add_measurement(measurement);
    }
    
    /// Get current latency statistics
    pub fn get_stats(&self) -> Option<LatencyStats> {
        let measurements = self.measurements.lock().ok()?;
        
        if measurements.is_empty() {
            return None;
        }
        
        let mut values: Vec<f64> = measurements
            .iter()
            .map(|m| m.input_to_output_ms)
            .collect();
        
        values.sort_by(|a, b| a.partial_cmp(b).unwrap());
        
        let min_ms = *values.first()?;
        let max_ms = *values.last()?;
        let avg_ms = values.iter().sum::<f64>() / values.len() as f64;
        
        let p50_idx = (values.len() * 50) / 100;
        let p95_idx = (values.len() * 95) / 100;
        let p99_idx = (values.len() * 99) / 100;
        
        let p50_ms = values[p50_idx.min(values.len() - 1)];
        let p95_ms = values[p95_idx.min(values.len() - 1)];
        let p99_ms = values[p99_idx.min(values.len() - 1)];
        
        Some(LatencyStats {
            min_ms,
            max_ms,
            avg_ms,
            p99_ms,
            p95_ms,
            p50_ms,
            samples: measurements.len(),
            last_update: Instant::now(),
        })
    }
    
    /// Get recent measurements (last N)
    pub fn get_recent_measurements(&self, count: usize) -> Vec<LatencyMeasurement> {
        if let Ok(measurements) = self.measurements.lock() {
            measurements
                .iter()
                .rev()
                .take(count)
                .rev()
                .cloned()
                .collect()
        } else {
            Vec::new()
        }
    }
    
    /// Get all measurements
    pub fn get_all_measurements(&self) -> Vec<LatencyMeasurement> {
        if let Ok(measurements) = self.measurements.lock() {
            measurements.iter().cloned().collect()
        } else {
            Vec::new()
        }
    }
    
    /// Clear all measurements
    pub fn clear_measurements(&self) {
        if let Ok(mut measurements) = self.measurements.lock() {
            measurements.clear();
        }
        log::info!("Cleared latency measurements");
    }
    
    /// Check if current latency meets the target
    pub fn meets_latency_target(&self, target_ms: f64) -> Option<bool> {
        let stats = self.get_stats()?;
        Some(stats.avg_ms <= target_ms && stats.p95_ms <= target_ms * 1.5)
    }
    
    /// Get a simple latency report as text
    pub fn get_report(&self) -> String {
        if let Some(stats) = self.get_stats() {
            format!(
                "Latency Report ({} samples):\n\
                 ├─ Average: {:.2} ms\n\
                 ├─ Median (P50): {:.2} ms\n\
                 ├─ P95: {:.2} ms\n\
                 ├─ P99: {:.2} ms\n\
                 ├─ Min: {:.2} ms\n\
                 ├─ Max: {:.2} ms\n\
                 ├─ Buffer: {:.2} ms\n\
                 └─ Target (20ms): {}",
                stats.samples,
                stats.avg_ms,
                stats.p50_ms,
                stats.p95_ms,
                stats.p99_ms,
                stats.min_ms,
                stats.max_ms,
                self.calculate_buffer_latency_ms(),
                if stats.avg_ms <= 20.0 && stats.p95_ms <= 30.0 {
                    "✓ PASS"
                } else {
                    "✗ FAIL"
                }
            )
        } else {
            "No latency measurements available".to_string()
        }
    }
}

/// Latency test runner for automated testing
pub struct LatencyTester {
    meter: Arc<LatencyMeter>,
    test_duration: Duration,
    test_interval: Duration,
}

impl LatencyTester {
    pub fn new(meter: Arc<LatencyMeter>, test_duration: Duration, test_interval: Duration) -> Self {
        Self {
            meter,
            test_duration,
            test_interval,
        }
    }
    
    /// Run an automated latency test
    pub fn run_test(&self, buffer_size: usize, sample_rate: usize) -> Option<LatencyStats> {
        log::info!("Starting automated latency test");
        log::info!("  Duration: {:?}", self.test_duration);
        log::info!("  Test interval: {:?}", self.test_interval);
        
        self.meter.clear_measurements();
        self.meter.start_measurement(buffer_size, sample_rate);
        
        let start_time = Instant::now();
        let mut test_count = 0;
        
        while start_time.elapsed() < self.test_duration {
            let test_start = Instant::now();
            
            // Inject a test signal (this would typically be done in audio callback)
            let _signal_id = self.meter.inject_test_signal();
            
            // Simulate processing delay (in real implementation, 
            // this would be the actual audio processing latency)
            let simulated_latency = Duration::from_micros(
                (buffer_size as f64 / sample_rate as f64 * 1_000_000.0) as u64
            );
            
            std::thread::sleep(simulated_latency);
            
            // Simulate signal detection (in real implementation, 
            // this would be done when the test signal is detected in input)
            self.meter.add_round_trip_measurement(test_start.elapsed());
            
            test_count += 1;
            std::thread::sleep(self.test_interval);
        }
        
        self.meter.stop_measurement();
        
        let stats = self.meter.get_stats();
        if let Some(ref stats) = stats {
            log::info!("Latency test completed:");
            log::info!("  Tests run: {}", test_count);
            log::info!("  Average latency: {:.2} ms", stats.avg_ms);
            log::info!("  P95 latency: {:.2} ms", stats.p95_ms);
            log::info!("  Target met: {}", 
                      if stats.avg_ms <= 20.0 { "Yes" } else { "No" });
        }
        
        stats
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_latency_meter_basic() {
        let meter = LatencyMeter::new(100);
        
        assert!(!meter.is_measuring());
        
        meter.start_measurement(256, 48000);
        assert!(meter.is_measuring());
        
        // Buffer latency should be around 5.33ms for 256 samples at 48kHz
        let buffer_latency = meter.calculate_buffer_latency_ms();
        assert!((buffer_latency - 5.33).abs() < 0.1);
        
        meter.stop_measurement();
        assert!(!meter.is_measuring());
    }
    
    #[test]
    fn test_measurements() {
        let meter = LatencyMeter::new(10);
        
        // Add some test measurements
        for i in 0..5 {
            meter.add_round_trip_measurement(Duration::from_millis(10 + i));
        }
        
        let stats = meter.get_stats().unwrap();
        assert_eq!(stats.samples, 5);
        assert!(stats.min_ms < stats.max_ms);
        assert!(stats.avg_ms > 0.0);
        
        let measurements = meter.get_all_measurements();
        assert_eq!(measurements.len(), 5);
        
        meter.clear_measurements();
        assert!(meter.get_stats().is_none());
    }
    
    #[test]
    fn test_latency_target() {
        let meter = LatencyMeter::new(10);
        
        // Add measurements that should meet 20ms target
        for _ in 0..5 {
            meter.add_round_trip_measurement(Duration::from_millis(30)); // 15ms input-to-output
        }
        
        assert!(meter.meets_latency_target(20.0).unwrap());
        assert!(!meter.meets_latency_target(5.0).unwrap()); // This should fail for 7.5ms input-to-output
    }
    
    #[test]
    fn test_automated_latency_test() {
        let meter = Arc::new(LatencyMeter::new(100));
        let tester = LatencyTester::new(
            meter.clone(),
            Duration::from_millis(100), // Short test
            Duration::from_millis(10),  // Frequent tests
        );
        
        let stats = tester.run_test(256, 48000);
        assert!(stats.is_some());
        
        let stats = stats.unwrap();
        assert!(stats.samples > 0);
        assert!(stats.avg_ms > 0.0);
    }
}