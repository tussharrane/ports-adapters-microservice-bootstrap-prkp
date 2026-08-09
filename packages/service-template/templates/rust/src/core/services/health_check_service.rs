use crate::core::models::health_status::HealthStatus;
use crate::ports::port_in::health_check_usecase_port_in::HealthCheckUseCasePortIn;

/// Placeholder health-check service — replace with real readiness checks (DB ping, Kafka connectivity, etc.).
pub struct HealthCheckService;

impl HealthCheckService {
    pub fn new() -> Self {
        Self
    }
}

impl Default for HealthCheckService {
    fn default() -> Self {
        Self::new()
    }
}

impl HealthCheckUseCasePortIn for HealthCheckService {
    fn check(&self) -> HealthStatus {
        HealthStatus { status: "ok".to_string() }
    }
}
