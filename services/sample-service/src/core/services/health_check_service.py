import os
import sys

# "in" is a Python keyword, so ports/in/ can't be dotted-imported
# (`ports.in.x` is a SyntaxError) — add its directory to sys.path and
# import it bare instead.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "ports", "in")))

from health_check_usecase_port_in import HealthCheckUseCasePortIn

from core.models.health_status import HealthStatus


class HealthCheckService(HealthCheckUseCasePortIn):
    """Placeholder health-check service — replace with real readiness checks (DB ping, Kafka connectivity, etc.)."""

    def check(self) -> HealthStatus:
        return HealthStatus(status="ok")
