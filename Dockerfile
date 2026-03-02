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

COPY Cargo.lock* ./
COPY essence/Cargo.toml essence/Cargo.toml
COPY webserver/Cargo.toml webserver/Cargo.toml
COPY webserver/build.rs webserver/build.rs
COPY harmony/Cargo.toml harmony/Cargo.toml
COPY convey/Cargo.toml convey/Cargo.toml

# workaround from <https://github.com/rust-lang/cargo/issues/2644>

RUN mkdir -p essence/src webserver/src harmony/src convey/src \
    && echo '' > essence/src/lib.rs \
    && echo 'fn main() {}' > webserver/src/main.rs \
    && echo 'fn main() {}' > harmony/src/main.rs \
    && echo 'fn main() {}' > convey/src/main.rs \
    && dd if=/dev/urandom bs=32 count=1 > webserver/secret.key 2>/dev/null
    
COPY essence/.sqlx essence/.sqlx

ARG WEBSERVER_DATABASE_URL
ARG WEBSERVER_REDIS_URL
ARG WEBSERVER_CDN_URL
ARG WEBSERVER_CDN_AUTH
ARG SECRET_KEY_PATH=webserver/secret.key

RUN --mount=type=cache,sharing=locked,target=/cargo/registry \
    --mount=type=cache,sharing=locked,target=/cargo/git \
    --mount=type=cache,sharing=locked,target=/build/target \
    CARGO_HOME=/cargo \
    DATABASE_URL="${WEBSERVER_DATABASE_URL}" \
    REDIS_URL="${WEBSERVER_REDIS_URL}" \
    CDN_URL="${WEBSERVER_CDN_URL:-placeholder}" \
    CDN_AUTHORIZATION="${WEBSERVER_CDN_AUTH:-placeholder}" \
    SECRET_KEY_PATH="/build/webserver/secret.key" \
    SQLX_OFFLINE=true \
    cargo build --workspace --all-features --release; \
    # remove ONLY workspace artifacts so deps stay cached
    rm -f  target/release/webserver \
           target/release/harmony \
           target/release/convey \
           target/release/deps/webserver* \
           target/release/deps/harmony* \
           target/release/deps/convey* \
           target/release/deps/essence* \
           target/release/deps/libessence* \
    && rm -rf target/release/.fingerprint/webserver-* \
              target/release/.fingerprint/harmony-* \
              target/release/.fingerprint/convey-* \
              target/release/.fingerprint/essence-*

COPY essence/ essence/
COPY webserver/ webserver/
COPY harmony/ harmony/
COPY convey/ convey/

RUN if [ ! -f webserver/secret.key ] && [ "${SECRET_KEY_PATH}" = "webserver/secret.key" ]; then \
      dd if=/dev/urandom bs=32 count=1 > webserver/secret.key 2>/dev/null; \
    fi

RUN --mount=type=cache,sharing=locked,target=/cargo/registry \
    --mount=type=cache,sharing=locked,target=/cargo/git \
    --mount=type=cache,sharing=locked,target=/build/target \
    CARGO_HOME=/cargo \
    cargo clean -p webserver -p essence -p harmony -p convey 2>/dev/null || true; \
    DATABASE_URL="${WEBSERVER_DATABASE_URL}" \
    REDIS_URL="${WEBSERVER_REDIS_URL}" \
    CDN_URL="${WEBSERVER_CDN_URL}" \
    CDN_AUTHORIZATION="${WEBSERVER_CDN_AUTH}" \
    SECRET_KEY_PATH="/build/${SECRET_KEY_PATH}" \
    SQLX_OFFLINE=true \
    cargo build --workspace --all-features --release \
    && cp target/release/webserver /webserver \
    && cp target/release/harmony /harmony \
    && cp target/release/convey /convey

FROM debian:bookworm-slim AS webserver

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /webserver /usr/local/bin/webserver
EXPOSE 8077
CMD ["webserver"]

FROM debian:bookworm-slim AS harmony

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /harmony /usr/local/bin/harmony
EXPOSE 8076
CMD ["harmony"]

FROM debian:bookworm-slim AS convey

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /convey /usr/local/bin/convey
WORKDIR /app
EXPOSE 8078
CMD ["convey"]
