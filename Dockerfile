# syntax=docker/dockerfile:1

FROM rustlang/rust:nightly-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY Cargo.toml Cargo.toml
COPY rust-toolchain.toml rust-toolchain.toml
COPY essence/ essence/
COPY webserver/ webserver/
COPY harmony/ harmony/
COPY convey/ convey/

ARG WEBSERVER_DATABASE_URL
ARG WEBSERVER_REDIS_URL
ARG WEBSERVER_CDN_URL
ARG WEBSERVER_CDN_AUTH
ARG SECRET_KEY_PATH=webserver/secret.key

RUN if [ ! -f webserver/secret.key ] && [ "${SECRET_KEY_PATH}" = "webserver/secret.key" ]; then \
      dd if=/dev/urandom bs=32 count=1 > webserver/secret.key 2>/dev/null; \
    fi

RUN DATABASE_URL="${WEBSERVER_DATABASE_URL}" \
    REDIS_URL="${WEBSERVER_REDIS_URL}" \
    CDN_URL="${WEBSERVER_CDN_URL}" \
    CDN_AUTHORIZATION="${WEBSERVER_CDN_AUTH}" \
    SECRET_KEY_PATH="/build/${SECRET_KEY_PATH}" \
    SQLX_OFFLINE=true \
    cargo build --workspace --all-features --release

FROM debian:bookworm-slim AS webserver

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/webserver /usr/local/bin/webserver
EXPOSE 8077
CMD ["webserver"]

FROM debian:bookworm-slim AS harmony

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/harmony /usr/local/bin/harmony
EXPOSE 8076
CMD ["harmony"]

FROM debian:bookworm-slim AS convey

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/convey /usr/local/bin/convey
WORKDIR /app
EXPOSE 8078
CMD ["convey"]
