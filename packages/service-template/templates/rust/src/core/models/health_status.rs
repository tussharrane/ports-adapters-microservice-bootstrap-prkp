use serde::Serialize;

/// Domain model returned by a health check.
#[derive(Debug, Clone, Serialize)]
pub struct HealthStatus {
    pub status: String,
}
