import os
import sys
from abc import ABC, abstractmethod

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from core.models.example import Example


class ExampleRepositoryPortOut(ABC):
    """Outbound port a domain service calls to persist/read an Example."""

    @abstractmethod
    def save(self, example: Example) -> None: ...

    @abstractmethod
    def find_by_id(self, id: str) -> Example | None: ...
