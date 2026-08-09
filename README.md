# ports-adapters-microservice-bootstrap

A ports-and-adapters microservice bootstrap: **P**ython, **R**ust,
**K**afka, **P**ostgres (**prkp**). Clone it, scaffold a new service in
either language with one command, and get a real Kafka
consumer/producer, a real Postgres repository, and a real health check
working immediately — wired through Docker Compose, locally and in
production.

`services/sample-service` is a real, committed example — build and run it
before writing anything of your own, to see the whole pattern working end
to end.

## Stack

- **Kafka** (KRaft mode, no ZooKeeper) — event bus
- **Postgres 16** — durable storage
- **Docker Compose** — one base file (`docker-compose.yml`) plus a local
  and a production environment overlay
- `packages/contracts` — protobuf event schemas, with codegen for Python
  and Rust
- `packages/infrastructure/modules/database` — dbmate SQL migrations,
  applied automatically by the `migrate` service on every
  `docker compose up`
- `packages/infrastructure/environments/{local,production}` — the two
  Compose overlays; local reads the root `.env.example`/`.env`,
  production has its own `.env.example`
- `packages/service-template` — Python and Rust ports-and-adapters
  skeletons (Kafka consumer/producer, Postgres repository, health
  listener), each with its own `Dockerfile`
- `pnpm workspaces` — monorepo tooling for `lint`/`typecheck` fanout
  across every scaffolded service

## Prerequisites

- Node.js >= 22
- pnpm 10.33.4 (pinned via the `packageManager` field — use
  [Corepack](https://nodejs.org/api/corepack.html) to match it exactly)
- Docker with Compose v2
- Python >= 3.11 (for `tomllib`, used by `scripts/new-service.sh` when
  scaffolding a Python service and by CI when installing each Python
  service's dependencies) — needed for the `--lang python` path of
  `scripts/new-service.sh`
- Rust toolchain (`cargo`), e.g. via [rustup](https://rustup.rs) — needed
  for the `--lang rust` path of `scripts/new-service.sh`
- **macOS only, for building/running a scaffolded service on the host**
  (not needed for the Dockerized path): `brew install librdkafka` — both
  templates' Kafka adapters link the native `librdkafka` library. Neither
  Dockerfile needs this host step: the Python image gets a prebuilt
  `librdkafka` via a manylinux wheel, and the Rust image builds
  `librdkafka` from source (Debian's `apt` package is too old for the
  Rust client, so the Dockerfile compiles it directly — see
  `packages/service-template/templates/rust/Dockerfile`).
- **For running migrations on the host**: `brew install dbmate` (only
  needed outside Docker — the `migrate` Compose service runs them
  automatically).
- **For regenerating `packages/contracts`** (`pnpm build` does this
  automatically): `buf` (`brew install bufbuild/buf/buf`), `protoc`
  (`brew install protobuf`), and `protoc-gen-prost`
  (`cargo install protoc-gen-prost` — installs to `$HOME/.cargo/bin`,
  which is not on `PATH` by default; see `packages/contracts/generate.sh`
  for the PATH export workaround).

## Getting started

```bash
cp .env.example .env
pnpm install
pnpm run build
pnpm infra:up
docker compose -f docker-compose.yml -f packages/infrastructure/environments/local/docker-compose.yml ps
```

`pnpm run build` regenerates `packages/contracts` and sets up
`services/sample-service`'s `.venv` (needed for `pnpm lint`/`pnpm typecheck`
to work on it — the Docker path below doesn't need this, but it's worth
running once anyway). `kafka` and `postgres` should report `healthy`;
`migrate` should report `Exited (0)` — it runs once per `up` and applies
any pending migrations from `packages/infrastructure/modules/database/migrations`.

Then build and run the committed sample service:

```bash
pnpm run service:up -- sample-service
curl http://localhost:8080
```

To stop everything:

```bash
pnpm run service:down -- sample-service
pnpm infra:down                                                                    # stop containers (local has no named volumes — data does not persist across this)
docker compose -f docker-compose.yml -f packages/infrastructure/environments/local/docker-compose.yml down -v   # same, plus remove the anonymous container volumes
```

For production, see [Production](#production) below.

### Local development (with Docker)

`pnpm run service:up -- <service-name> [host-port]` (used above for
`sample-service`) works the same way for any service you scaffold
yourself:

```bash
scripts/new-service.sh my-service --lang python   # or --lang rust
pnpm run service:up -- my-service
```

builds `services/<service-name>`'s image and runs it on the Compose
network (reaching `postgres`/`kafka` by their in-network names, reading
`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` from your `.env`),
mapping container port `8080` to `host-port` on your machine (defaults to
`8080` if omitted — pick a different one if you're running more than one
service at a time). After changing a service's code, rebuild and restart
to pick it up — there's no live-reload — by just running `service:up`
again.

### Kafka host vs. in-network access

Kafka exposes two listeners:

- From the **bare host** (tests, `kafka-topics.sh`, a host-run service):
  `localhost:${KAFKA_HOST_PORT:-29092}`
- From **inside the Docker network** (any service defined in a Compose
  file): `kafka:9092`

Topic auto-creation is enabled in local dev
(`KAFKA_AUTO_CREATE_TOPICS_ENABLE=true`) and explicitly disabled in
production (`KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`) — no central topic
registry exists yet (only two placeholder topic names hardcoded as
defaults in the service templates), so the local default is a deliberate
simplicity call, not a permanent policy. Revisit once your own services
and their topics are decided.

Postgres is reachable from the host at
`postgres://<POSTGRES_USER>:<POSTGRES_PASSWORD>@localhost:${POSTGRES_HOST_PORT:-5433}/<POSTGRES_DB>`
(port **5433** by default, not 5432, so it can run alongside another
local Postgres instance).

## Production

Production uses the same base `docker-compose.yml` with a different
overlay — `restart: unless-stopped`, named persistent volumes for
Kafka/Postgres data, and no host port exposure beyond what's actually
needed:

```bash
cp packages/infrastructure/environments/production/.env.example \
   packages/infrastructure/environments/production/.env
# edit that .env with real production credentials — it is gitignored, never commit it
pnpm infra:up:prod
```

This is still a single-host Docker Compose deployment with
production-appropriate settings — no cloud provider, container registry,
TLS termination, or multi-host/orchestrator decision is made here.

## Repo layout

```
packages/
  contracts/                        # protobuf event schemas + codegen (Python, Rust)
  infrastructure/
    modules/database/               # dbmate SQL migrations, shared schema
    environments/
      local/                         # local Compose overlay (reads the root .env.example/.env)
      production/                    # production Compose overlay + its own .env.example
  service-template/
    templates/python/                # Python skeleton + Dockerfile
    templates/rust/                  # Rust skeleton + Dockerfile
services/
  sample-service/                   # a real, committed Python service — build and run this first
scripts/
  new-service.sh                    # scaffold a new service (see below)
  dev-service.sh                    # build + run (or stop) one service's Docker image for local dev
  build.sh                          # regenerate contracts + build every service's Docker image
docs/
  ports-and-adapters.md             # the pattern, explained
.github/workflows/ci.yml              # lint + typecheck on every push/PR
docker-compose.yml                   # shared Kafka/Postgres/migrate service definitions
.env.example                          # root env defaults, used by the local overlay
LICENSE                               # MIT
```

Every service under `services/` is structured as **ports and adapters**
(`ports/`, `adapters/`, `core/`) — see
[`docs/ports-and-adapters.md`](docs/ports-and-adapters.md) for a full
explanation of the pattern before adding a new service.

## Adding a new service

To scaffold a new one:

```bash
scripts/new-service.sh <service-name> --lang python|rust
# e.g. scripts/new-service.sh risk-execution-service --lang rust
pnpm run build
```

This copies the matching skeleton from
`packages/service-template/templates/<lang>/` into
`services/<service-name>/` and substitutes the service name into it —
including its `Dockerfile`, so the scaffolded service is ready to build
immediately (`docker build services/<service-name>`). `pnpm run build`
sets up the new Python service's `.venv` (skip it for a Rust service —
`cargo run` needs nothing extra) and regenerates `packages/contracts`;
run it once after scaffolding, before `.venv/bin/python3 main.py` or
`pnpm run service:up`.

Scaffolded services expect a running Postgres and a `DATABASE_URL`
environment variable — there is no default, unlike Kafka's
`localhost:9092`/`kafka:9092`.

To wire the new service into Docker Compose, add a service block to
`packages/infrastructure/environments/local/docker-compose.yml` (and the
production overlay, once you're ready to deploy it there):

```yaml
services:
  <service-name>:
    build:
      context: ./services/<service-name>
    depends_on:
      migrate:
        condition: service_completed_successfully
    environment:
      KAFKA_BROKERS: kafka:9092
      KAFKA_GROUP_ID: <service-name>
      DATABASE_URL: postgres://${POSTGRES_USER:-app}:${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}@postgres:5432/${POSTGRES_DB:-bootstrap}?sslmode=disable
      HEALTH_HOST: 0.0.0.0
      HEALTH_PORT: 8080
    ports:
      - "<a free host port>:8080"
```

## Scripts

Every push/PR also runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
(`pnpm lint` + `pnpm typecheck`, including setting up a venv for every
Python service under `services/`).

| Script                 | Description                                                  |
| ----------------------- | -------------------------------------------------------------- |
| `pnpm build`             | Regenerate `packages/contracts`, then build a Docker image for every service under `services/` |
| `pnpm lint`              | Run ESLint, plus every workspace package/service's own lint script |
| `pnpm typecheck`         | Typecheck every workspace package/service that has one         |
| `pnpm infra:up`          | Start Kafka + Postgres (local) and run pending migrations      |
| `pnpm infra:down`        | Stop the local Docker Compose stack                             |
| `pnpm infra:up:prod`     | Start Kafka + Postgres (production overlay)                     |
| `pnpm infra:down:prod`   | Stop the production Docker Compose stack                        |
| `pnpm new-service -- <name> --lang <python\|rust>` | Scaffold a new service                    |
| `pnpm service:up -- <name> [host-port]` | Build and run one service's Docker image against the local Compose network |
| `pnpm service:down -- <name>` | Stop and remove that service's container/image |

## License

[MIT](LICENSE).
