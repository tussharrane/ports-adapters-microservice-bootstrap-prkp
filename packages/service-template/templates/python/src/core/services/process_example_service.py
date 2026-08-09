import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
# "in" is a Python keyword, so ports/in/ can't be dotted-imported
# (`ports.in.x` is a SyntaxError) — add its directory to sys.path and
# import it bare instead.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "ports", "in")))

from process_example_usecase_port_in import ProcessExampleUseCasePortIn

from core.models.example import Example
from ports.out.example_publisher_port_out import ExamplePublisherPortOut
from ports.out.example_repository_port_out import ExampleRepositoryPortOut


class ProcessExampleService(ProcessExampleUseCasePortIn):
    """Placeholder domain service — replace with this service's real logic."""

    def __init__(
        self,
        publisher: ExamplePublisherPortOut,
        repository: ExampleRepositoryPortOut,
    ) -> None:
        self._publisher = publisher
        self._repository = repository

    def process(self, example: Example) -> None:
        self._repository.save(example)
        self._publisher.publish(example)
