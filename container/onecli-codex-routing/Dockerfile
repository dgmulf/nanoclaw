FROM ghcr.io/onecli/onecli@sha256:8d4a3300e915259a2fcff13614ecd7394bfd35c75d6a64d69f28a28dd23f30fe
COPY patch.cjs /tmp/codex-routing-patch.cjs
RUN node /tmp/codex-routing-patch.cjs '/app/apps/web/.next/server/chunks/[root-of-the-server]__e964b775._.js' \
    && node --check '/app/apps/web/.next/server/chunks/[root-of-the-server]__e964b775._.js'
