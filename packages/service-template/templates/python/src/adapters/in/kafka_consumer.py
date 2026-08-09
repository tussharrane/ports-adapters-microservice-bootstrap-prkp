import os
import sys
import threading

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "generated")))
# "in" is a Python keyword, so ports/in/ can't be dotted-imported
# (`ports.in.x` is a SyntaxError) — add its directory to sys.path and
# import it bare instead.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "ports", "in")))

from confluent_kafka import Consumer
from example.v1 import example_pb2
from process_example_usecase_port_in import ProcessExampleUseCasePortIn

from core.models.example import Example


class KafkaConsumer:
    def __init__(self, usecase: ProcessExampleUseCasePortIn) -> None:
        self._usecase = usecase
        brokers = os.environ.get("KAFKA_BROKERS", "localhost:9092")
        self._topic = os.environ.get("KAFKA_CONSUME_TOPIC", "example.v1.in")
        group_id = os.environ.get("KAFKA_GROUP_ID", "__service_name__")
        self._consumer = Consumer(
            {
                "bootstrap.servers": brokers,
                "group.id": group_id,
                "auto.offset.reset": "earliest",
            }
        )
        self._consumer.subscribe([self._topic])

    def start(self, stop_event: threading.Event) -> None:
        while not stop_event.is_set():
            msg = self._consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print(f"__SERVICE_NAME__: consume error: {msg.error()}", file=sys.stderr, flush=True)
                continue
            value = msg.value()
            if value is None:
                continue
            generated = example_pb2.Example()
            generated.ParseFromString(value)
            example = Example(id=generated.id, payload=generated.payload)
            self._usecase.process(example)
        self._consumer.close()
        print("__SERVICE_NAME__: consumer closed cleanly", file=sys.stderr, flush=True)
