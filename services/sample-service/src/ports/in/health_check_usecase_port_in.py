import os
import sys
from abc import ABC, abstractmethod

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from core.models.health_status import HealthStatus


class HealthCheckUseCasePortIn(ABC):
    """Inbound port an adapters/in calls to drive the domain."""

    @abstractmethod
    def check(self) -> HealthStatus: ...
