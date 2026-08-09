# Ports and adapters in this repo

Every service under `services/` (scaffolded from
`packages/service-template/templates/`) is structured as **ports and
adapters** (also called hexagonal architecture). This document explains
what that means here, then walks through the reference implementation
every scaffolded service starts from.

## The idea, in one paragraph

A service's actual logic — the thing worth testing, the thing that would
survive swapping Kafka for something else — should never import a
concrete technology directly: no `confluent_kafka`, no `psycopg`, no
`rdkafka`. Instead it depends on small interfaces (**ports**) that
describe *what it needs from the outside world*, in its own vocabulary.
Separately, **adapters** are concrete classes that implement those
interfaces using a real technology. The composition root (`main.py` /
`main.rs`) constructs the real adapters and wires them into the logic at
startup — the only place in a service allowed to do that.

## The three directories

Each of `ports/`, `adapters/`, and `core/` splits further by direction or
role:

- **`ports/in/`** — interfaces an `adapters/in/` class calls to drive the
  domain. E.g. `ProcessExampleUseCasePortIn.process(example)`,
  `HealthCheckUseCasePortIn.check()`.
- **`ports/out/`** — interfaces a `core/services/` class calls to reach
  infrastructure. E.g. `ExampleRepositoryPortOut.save(example)`,
  `ExamplePublisherPortOut.publish(example)`.
- **`adapters/in/`** — real inbound triggers. `KafkaConsumer` polls Kafka,
  decodes the protobuf message, and calls a `ports/in/` interface.
  `HealthListener` is a raw TCP liveness probe that calls
  `HealthCheckUseCasePortIn.check()` on every request.
- **`adapters/out/`** — real infrastructure implementations of
  `ports/out/` interfaces. `KafkaProducer` implements
  `ExamplePublisherPortOut`. The Postgres repository implements
  `ExampleRepositoryPortOut`.
- **`core/models/`** — plain domain data, no library imports at all
  (`Example`, `HealthStatus`).
- **`core/services/`** — the actual logic. `ProcessExampleService`
  implements `ProcessExampleUseCasePortIn`, and itself only calls
  `ExampleRepositoryPortOut`/`ExamplePublisherPortOut` — never a concrete
  adapter class. `HealthCheckService` implements
  `HealthCheckUseCasePortIn`.

## Worked example: one Kafka message, end to end

1. `adapters/in/kafka_consumer.py`'s `KafkaConsumer.start()` polls Kafka,
   gets a message on the consume topic, and decodes it into the generated
   protobuf `Example` type.
2. It calls `self._usecase.process(example)` — `self._usecase` is typed as
   `ProcessExampleUseCasePortIn`, not as `ProcessExampleService`. The
   consumer has no idea what happens next, only that *something* that
   satisfies the port interface will handle it.
3. `core/services/process_example_service.py`'s `ProcessExampleService`
   (the concrete class actually wired in) calls
   `self._repository.save(example)` then `self._publisher.publish(example)`
   — both are port interfaces (`ExampleRepositoryPortOut`,
   `ExamplePublisherPortOut`), not concrete classes.
4. The real `adapters/out/` classes do the actual work: the Postgres
   repository issues a real `INSERT`, `KafkaProducer` issues a real
   `produce()` onto the publish topic.

The health check follows the identical shape with one fewer hop:
`adapters/in/health_listener.py`'s `HealthListener` calls
`HealthCheckUseCasePortIn.check()` on every incoming connection;
`core/services/health_check_service.py`'s `HealthCheckService` is the
concrete implementation actually wired in, and today just returns a
static `HealthStatus(status="ok")` — replace it with real readiness
checks (a Postgres ping, Kafka connectivity) when you need them.

## The composition root

`main.py` / `main.rs` is the *only* place allowed to construct a concrete
adapter or service and hand it to another. It builds the real Postgres
pool, the real `KafkaProducer`, the real `ProcessExampleService` (handing
it the publisher and repository), the real `KafkaConsumer` (handing it the
service), the real `HealthCheckService`, and the real `HealthListener`
(handing it the health-check service — `HealthListener`'s own constructor
registers the `SIGTERM`/`SIGINT` handlers against a shared stop signal, not
`main.py`/`main.rs` itself) — then starts the health listener on a
background thread and runs the Kafka consumer loop on the main thread.
Nothing here contains domain logic; it's wiring, and wiring only.

## The rule that keeps this from rotting

**`core/` files depend only on types from `ports/`, never on a concrete
class from `adapters/`.** If you ever find yourself importing
`KafkaProducer` or a Postgres class directly into `core/services/`, the
boundary has already leaked — the fix is always to add a method to the
relevant port interface instead, and let the composition root wire in
whichever adapter implements it.

This is also what makes the pattern testable without live infrastructure:
a test for `ProcessExampleService` can hand it a fake
`ExampleRepositoryPortOut`/`ExamplePublisherPortOut` (a plain in-memory
class implementing the same two methods) instead of a real Postgres
connection or Kafka producer, and assert on what the fakes recorded — no
Docker, no network, no flakiness. This repo doesn't ship a test suite
today, but the seam for adding one is already there in every scaffolded
service.

## Adding this to a new service

`scripts/new-service.sh` scaffolds all three directories with the working
reference implementation above, not empty stubs. When you build your own
logic on top:

1. Write the `ports/` interface first — what does your logic actually
   need from the outside world, in your own words? Not "a
   `confluent_kafka.Producer`" — "a way to publish this event."
2. Write your `core/services/` class against that port interface only.
3. Write the `adapters/` class that implements the port using the real
   technology — or a fake one first, if the real integration doesn't
   exist yet.
4. Wire the real adapter into your service from `main.py`/`main.rs`, and
   nowhere else.

See the README's [Local development](../README.md#local-development-with-docker)
section for building and running a scaffolded service against the same
Compose network while you iterate on its logic.
