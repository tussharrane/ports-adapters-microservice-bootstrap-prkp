from dataclasses import dataclass


@dataclass
class HealthStatus:
    """Domain model returned by a health check."""

    status: str
