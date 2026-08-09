import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "generated")))

from confluent_kafka import Producer
from example.v1 import example_pb2

from core.models.example import Example
from ports.out.example_publisher_port_out import ExamplePublisherPortOut


def _log_delivery_failure(err, _msg) -> None:
    if err is not None:
        print(f"__SERVICE_NAME__: Kafka delivery failed: {err}", file=sys.stderr, flush=True)


class KafkaProducer(ExamplePublisherPortOut):
    def __init__(self) -> None:
        brokers = os.environ.get("KAFKA_BROKERS", "localhost:9092")
        self._topic = os.environ.get("KAFKA_PRODUCE_TOPIC", "example.v1.out")
        self._producer = Producer({"bootstrap.servers": brokers})

    def publish(self, example: Example) -> None:
        generated = example_pb2.Example(id=example.id, payload=example.payload)
        data = generated.SerializeToString()
        self._producer.produce(self._topic, key=example.id, value=data, callback=_log_delivery_failure)
        remaining = self._producer.flush(5)
        if remaining > 0:
            print(
                f"__SERVICE_NAME__: Kafka flush timed out with {remaining} message(s) undelivered",
                file=sys.stderr,
                flush=True,
            )
        print(f"[__SERVICE_NAME__] published {len(data)} bytes to {self._topic}", flush=True)
