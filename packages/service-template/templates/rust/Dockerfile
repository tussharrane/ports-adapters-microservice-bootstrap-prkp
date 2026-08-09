FROM rust:1-slim-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libzstd-dev \
    liblz4-dev \
    libcurl4-openssl-dev \
    pkg-config \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/confluentinc/librdkafka/archive/refs/tags/v2.12.1.tar.gz -o /tmp/librdkafka.tar.gz \
    && tar xzf /tmp/librdkafka.tar.gz -C /tmp \
    && cd /tmp/librdkafka-2.12.1 \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && rm -rf /tmp/librdkafka*

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY generated ./generated
COPY src ./src

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    zlib1g \
    libzstd1 \
    liblz4-1 \
    libcurl4 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/librdkafka.so* /usr/local/lib/
RUN ldconfig && useradd --create-home --shell /bin/bash appuser

WORKDIR /app
COPY --from=builder /app/target/release/__service_name__ ./__service_name__

USER appuser

CMD ["./__service_name__"]
