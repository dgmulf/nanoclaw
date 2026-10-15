# OneCLI 1.42.0 source, pinned independently of the upstream tag.
FROM rust:1.91.1-alpine3.22@sha256:8efbfb788786eeb127adc581394349c5fb567712156e0f8c2e499acadbc23756 AS gateway-builder
RUN apk add --no-cache musl-dev pkgconfig openssl-dev openssl-libs-static patch
ADD --checksum=sha256:2a12554279d74b1bc71e73253cbe3b0fb3825a7b16f8d800cf166cd7af71ffe1 https://api.github.com/repos/onecli/onecli/tarball/3912c74d7029505f0f5389745568111d643adc68 /tmp/onecli.tar.gz
RUN mkdir /source && tar -xzf /tmp/onecli.tar.gz -C /source --strip-components=1
COPY openai-refresh.patch /tmp/openai-refresh.patch
RUN cd /source && patch --batch --fuzz=0 -p1 < /tmp/openai-refresh.patch
WORKDIR /source/apps/gateway
# Keep memory bounded on small deployment machines. The upstream lockfile is unchanged.
ENV CARGO_BUILD_JOBS=2
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/source/apps/gateway/target \
    cargo test --locked --release --bin onecli-gateway \
    && cargo build --locked --release \
    && cp target/release/onecli-gateway /tmp/onecli-gateway

FROM ghcr.io/onecli/onecli@sha256:8d4a3300e915259a2fcff13614ecd7394bfd35c75d6a64d69f28a28dd23f30fe
COPY --from=gateway-builder /tmp/onecli-gateway /usr/local/bin/onecli-gateway
COPY patch.cjs /tmp/codex-routing-patch.cjs
RUN node /tmp/codex-routing-patch.cjs '/app/apps/web/.next/server/chunks/[root-of-the-server]__e964b775._.js' \
    && node --check '/app/apps/web/.next/server/chunks/[root-of-the-server]__e964b775._.js'
LABEL io.nanoclaw.onecli-patches="codex-account-routing,openai-refresh-client-id"
