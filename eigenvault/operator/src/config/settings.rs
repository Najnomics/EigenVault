use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub operator: OperatorSettings,
    pub performance: PerformanceSettings,
    pub security: SecuritySettings,
    pub monitoring: MonitoringSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorSettings {
    pub operator_id: String,
    pub metadata_url: String,
    pub stake_amount: String,
    pub commission_rate_bps: u64,
    pub auto_restart: bool,
    pub max_concurrent_tasks: usize,
    pub task_timeout_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceSettings {
    pub thread_pool_size: usize,
    pub memory_limit_mb: usize,
    pub disk_cache_size_mb: usize,
    pub network_buffer_size: usize,
    pub batch_processing_size: usize,
    pub parallel_proof_generation: bool,
    pub use_gpu_acceleration: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecuritySettings {
    pub enable_secure_boot: bool,
    pub require_signature_verification: bool,
    pub key_rotation_interval_hours: u64,
    pub max_failed_attempts: u32,
    pub lockout_duration_minutes: u32,
    pub trusted_peers: Vec<String>,
    pub blacklisted_addresses: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringSettings {
    pub enable_metrics: bool,
    pub metrics_port: u16,
    pub enable_health_checks: bool,
    pub health_check_interval_seconds: u64,
    pub enable_alerting: bool,
    pub alert_endpoints: Vec<AlertEndpoint>,
    pub log_performance_metrics: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlertEndpoint {
    pub name: String,
    pub endpoint_type: AlertType,
    pub url: String,
    pub auth_token: Option<String>,
    pub severity_threshold: AlertSeverity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AlertType {
    Webhook,
    Email,
    Slack,
    Discord,
    PagerDuty,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AlertSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            operator: OperatorSettings {
                operator_id: "eigenvault-operator-1".to_string(),
                metadata_url: "https://your-operator-metadata.json".to_string(),
                stake_amount: "32000000000000000000".to_string(), // 32 ETH
                commission_rate_bps: 1000, // 10%
                auto_restart: true,
                max_concurrent_tasks: 10,
                task_timeout_seconds: 300,
            },
            performance: PerformanceSettings {
                thread_pool_size: num_cpus::get(),
                memory_limit_mb: 4096,
                disk_cache_size_mb: 1024,
                network_buffer_size: 65536,
                batch_processing_size: 100,
                parallel_proof_generation: true,
                use_gpu_acceleration: false,
            },
            security: SecuritySettings {
                enable_secure_boot: true,
                require_signature_verification: true,
                key_rotation_interval_hours: 24 * 7, // Weekly
                max_failed_attempts: 5,
                lockout_duration_minutes: 15,
                trusted_peers: vec![],
                blacklisted_addresses: vec![],
            },
            monitoring: MonitoringSettings {
                enable_metrics: true,
                metrics_port: 9090,
                enable_health_checks: true,
                health_check_interval_seconds: 30,
                enable_alerting: false,
                alert_endpoints: vec![],
                log_performance_metrics: true,
            },
        }
    }
}

impl Settings {
    pub fn validate(&self) -> anyhow::Result<()> {
        // Validate operator settings
        if self.operator.operator_id.is_empty() {
            return Err(anyhow::anyhow!("Operator ID cannot be empty"));
        }

        if self.operator.commission_rate_bps > 10000 {
            return Err(anyhow::anyhow!("Commission rate cannot exceed 100%"));
        }

        // Validate performance settings
        if self.performance.thread_pool_size == 0 {
            return Err(anyhow::anyhow!("Thread pool size must be greater than 0"));
        }

        if self.performance.memory_limit_mb < 512 {
            return Err(anyhow::anyhow!("Memory limit must be at least 512MB"));
        }

        // Validate monitoring settings
        if self.monitoring.metrics_port < 1024 {
            return Err(anyhow::anyhow!("Metrics port should be >= 1024"));
        }

        Ok(())
    }

    pub fn get_recommended_settings_for_hardware() -> Self {
        let cpu_count = num_cpus::get();
        let available_memory = Self::get_available_memory_mb();

        let mut settings = Self::default();

        // Adjust based on available resources
        settings.performance.thread_pool_size = (cpu_count as f64 * 1.5) as usize;
        settings.performance.memory_limit_mb = (available_memory as f64 * 0.8) as usize;
        settings.performance.disk_cache_size_mb = std::cmp::min(
            available_memory / 4,
            2048,
        );

        // Enable GPU acceleration if available
        settings.performance.use_gpu_acceleration = Self::has_gpu_support();

        settings
    }

    fn get_available_memory_mb() -> usize {
        // Platform-specific memory detection
        #[cfg(target_os = "linux")]
        {
            if let Ok(content) = std::fs::read_to_string("/proc/meminfo") {
                for line in content.lines() {
                    if line.starts_with("MemAvailable:") {
                        if let Some(kb_str) = line.split_whitespace().nth(1) {
                            if let Ok(kb) = kb_str.parse::<usize>() {
                                return kb / 1024; // Convert to MB
                            }
                        }
                    }
                }
            }
        }

        // Default fallback
        4096 // 4GB
    }

    fn has_gpu_support() -> bool {
        // Simplified GPU detection
        // In production, would use proper GPU detection libraries
        std::env::var("CUDA_VISIBLE_DEVICES").is_ok() ||
        std::path::Path::new("/dev/nvidia0").exists()
    }

    pub fn optimize_for_environment(&mut self, environment: &str) {
        match environment {
            "development" => {
                self.performance.memory_limit_mb = 1024;
                self.performance.thread_pool_size = 2;
                self.monitoring.enable_metrics = false;
                self.security.enable_secure_boot = false;
            }
            "testing" => {
                self.performance.memory_limit_mb = 2048;
                self.performance.thread_pool_size = 4;
                self.operator.max_concurrent_tasks = 5;
                self.security.max_failed_attempts = 10;
            }
            "staging" => {
                self.performance.memory_limit_mb = 4096;
                self.monitoring.enable_alerting = true;
                self.security.require_signature_verification = true;
            }
            "production" => {
                self.security.enable_secure_boot = true;
                self.security.require_signature_verification = true;
                self.monitoring.enable_alerting = true;
                self.monitoring.enable_health_checks = true;
                self.operator.auto_restart = true;
            }
            _ => {
                // Use default settings
            }
        }
    }

    pub fn get_memory_settings(&self) -> MemorySettings {
        MemorySettings {
            heap_size_mb: self.performance.memory_limit_mb * 7 / 10, // 70% for heap
            cache_size_mb: self.performance.disk_cache_size_mb,
            buffer_size_bytes: self.performance.network_buffer_size,
        }
    }

    pub fn get_concurrency_settings(&self) -> ConcurrencySettings {
        ConcurrencySettings {
            max_threads: self.performance.thread_pool_size,
            max_concurrent_tasks: self.operator.max_concurrent_tasks,
            batch_size: self.performance.batch_processing_size,
            parallel_processing: self.performance.parallel_proof_generation,
        }
    }
}

#[derive(Debug, Clone)]
pub struct MemorySettings {
    pub heap_size_mb: usize,
    pub cache_size_mb: usize,
    pub buffer_size_bytes: usize,
}

#[derive(Debug, Clone)]
pub struct ConcurrencySettings {
    pub max_threads: usize,
    pub max_concurrent_tasks: usize,
    pub batch_size: usize,
    pub parallel_processing: bool,
}

// Environment detection utilities
pub fn detect_environment() -> String {
    if let Ok(env) = std::env::var("EIGENVAULT_ENV") {
        return env.to_lowercase();
    }

    if let Ok(env) = std::env::var("NODE_ENV") {
        return env.to_lowercase();
    }

    if cfg!(debug_assertions) {
        "development".to_string()
    } else {
        "production".to_string()
    }
}

pub fn load_environment_overrides() -> HashMap<String, String> {
    let mut overrides = HashMap::new();

    // Load from environment variables with EIGENVAULT_ prefix
    for (key, value) in std::env::vars() {
        if key.starts_with("EIGENVAULT_") {
            let config_key = key.strip_prefix("EIGENVAULT_").unwrap().to_lowercase();
            overrides.insert(config_key, value);
        }
    }

    overrides
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_settings_validation() {
        let settings = Settings::default();
        assert!(settings.validate().is_ok());
    }

    #[test]
    fn test_invalid_commission_rate() {
        let mut settings = Settings::default();
        settings.operator.commission_rate_bps = 15000; // 150%
        
        assert!(settings.validate().is_err());
    }

    #[test]
    fn test_environment_optimization() {
        let mut settings = Settings::default();
        let original_memory = settings.performance.memory_limit_mb;
        
        settings.optimize_for_environment("development");
        assert!(settings.performance.memory_limit_mb < original_memory);
        assert!(!settings.monitoring.enable_metrics);
    }

    #[test]
    fn test_memory_settings() {
        let settings = Settings::default();
        let memory_settings = settings.get_memory_settings();
        
        assert!(memory_settings.heap_size_mb > 0);
        assert!(memory_settings.cache_size_mb > 0);
    }

    #[test]
    fn test_environment_detection() {
        let env = detect_environment();
        assert!(!env.is_empty());
    }
}