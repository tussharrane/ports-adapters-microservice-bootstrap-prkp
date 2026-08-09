use crate::core::models::health_status::HealthStatus;

pub trait HealthCheckUseCasePortIn: Send {
    fn check(&self) -> HealthStatus;
}
