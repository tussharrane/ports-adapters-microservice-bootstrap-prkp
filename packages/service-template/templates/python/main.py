import os
import sys
import threading

from psycopg_pool import ConnectionPool

_SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "src"))
sys.path.insert(0, _SRC)
# "in" is a Python keyword, so adapters/in/ can't be dotted-imported.
sys.path.insert(0, os.path.join(_SRC, "adapters", "in"))

from health_listener import HealthListener
from kafka_consumer import KafkaConsumer

from adapters.out.kafka_producer import KafkaProducer
from adapters.out.postgres_example_repository import PostgresExampleRepository
from core.services.health_check_service import HealthCheckService
from core.services.process_example_service import ProcessExampleService


def main() -> None:
    database_url = os.environ["DATABASE_URL"]
    pool = ConnectionPool(database_url, min_size=1, max_size=5, open=True)
    pool.wait(timeout=5)

    adapter_out_kafka_producer = KafkaProducer()
    adapter_out_postgres_repository = PostgresExampleRepository(pool)
    example_service = ProcessExampleService(adapter_out_kafka_producer, adapter_out_postgres_repository)
    adapter_in_kafka_consumer = KafkaConsumer(example_service)

    stop_event = threading.Event()

    health_check_service = HealthCheckService()
    adapter_in_health_listener = HealthListener(health_check_service, stop_event)
    health_thread = threading.Thread(target=adapter_in_health_listener.start, daemon=True)
    health_thread.start()

    adapter_in_kafka_consumer.start(stop_event)


if __name__ == "__main__":
    main()
