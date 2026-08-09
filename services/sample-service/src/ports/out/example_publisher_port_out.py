import os
import sys
from abc import ABC, abstractmethod

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from core.models.example import Example


class ExamplePublisherPortOut(ABC):
    """Outbound port a domain service calls to publish an Example."""

    @abstractmethod
    def publish(self, example: Example) -> None: ...
