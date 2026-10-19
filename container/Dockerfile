# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e
# The BuildKit frontend above is pinned by digest, so a build fetches it by
# content address and never asks Docker Hub to resolve the `1.7` tag first. The
# tag lookup is the HEAD request that returned 500 and took two registry-skills
# legs down on 2026-09-07 with the code untouched. Resolved with
# `crane digest docker/dockerfile:1.7` (docker buildx imagetools inspect agrees).
# Bump the tag and digest together.
# NanoClaw Agent Container
# Runs Claude Agent SDK in isolated Linux VM with browser automation.
#
# Runtime split:
#   - agent-runner (our TypeScript code): Bun, mounted RO at /app/src by host
#   - globally-installed Node CLIs (claude-code, agent-browser): pnpm + Node
#
# Source is never baked in — /app/src is provided by a shared read-only
# bind mount at runtime (see src/container-runner.ts). Source-only changes
# never require an image rebuild.

FROM node:22-slim

# ---- Build-time arguments ----------------------------------------------------
# CJK fonts add ~200MB. Opt in only if you render Chinese/Japanese/Korean text.
ARG INSTALL_CJK_FONTS=false

# Pin versions for reproducibility. Bump deliberately — unpinned installs mean
# every rebuild silently picks up the latest and can break in lockstep across
# all users. The global Node CLIs (claude-code, agent-browser) are
# pinned in cli-tools.json so a skill can add one with a json-merge; Bun (the
# runtime) is pinned here because it installs from a different source.
ARG BUN_VERSION=1.4.0

# ---- System dependencies -----------------------------------------------------
# tini: correct PID 1 / signal forwarding so outbound.db writes finalize on
# SIGTERM instead of being orphaned by the shell entrypoint.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        chromium \
        fonts-liberation \
        fonts-noto-color-emoji \
        libgbm1 \
        libnss3 \
        libnss3-tools \
        libatk-bridge2.0-0 \
        libgtk-3-0 \
        libx11-xcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libasound2 \
        libpangocairo-1.0-0 \
        libcups2 \
        libdrm2 \
        libxshmfence1 \
        ca-certificates \
        curl \
        git \
        tini \
        unzip \
    && if [ "$INSTALL_CJK_FONTS" = "true" ]; then \
        apt-get install -y --no-install-recommends fonts-noto-cjk; \
       fi \
    && rm -rf /var/lib/apt/lists/*

# Chromium path for agent-browser / Playwright consumers
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
# Belt-and-braces: prevent Playwright's postinstall from downloading its own
# ~300MB Chromium. We've already installed the system one above.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# ---- Bun runtime -------------------------------------------------------------
# Install via the official script (handles multi-arch detection), then move
# the binary to /usr/local/bin so the non-root `node` user can execute it.
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" && \
    install -m 0755 /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /root/.bun

# ---- agent-runner deps -------------------------------------------------------
# Deps are cached independently of CLI versions. Source is NOT baked in —
# it's provided by the shared RO mount at runtime.
WORKDIR /app

COPY agent-runner/package.json agent-runner/bun.lock ./

RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile

# ---- pnpm + global Node CLIs -------------------------------------------------
# Most stable first, most frequently bumped last. Bumping claude-code
# (the most common change) only invalidates one layer.
#
# only-built-dependencies gates pnpm's supply-chain policy:
#   - agent-browser has a postinstall build step.
#   - @anthropic-ai/claude-code's postinstall downloads the native Claude
#     binary (linux-arm64 variant on our image). Without the allowlist
#     the SDK fails at spawn time with "native binary not found".
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
# Pin pnpm to match the host (package.json packageManager). pnpm 11 stopped
# honoring `only-built-dependencies[]=` in .npmrc for global installs, which
# silently skips claude-code's native-binary postinstall and agent-browser's
# bin chmod — the agent then crashes at runtime with "native binary not
# installed". Keep this in lockstep with package.json's `packageManager`.
ARG PNPM_VERSION=10.34.5
RUN corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate

# The npm bundled with node:22-slim (10.9.8) vendors tar <7.5.19, which
# carries a fixable critical (GHSA-23hp-3jrh-7fpw) that the publish gate
# refuses to ship. Patch-level bump only. Drop this once the base image
# ships npm >= 10.9.9.
ARG NPM_VERSION=10.9.9
RUN npm install -g npm@${NPM_VERSION}

# Global Node CLIs the agent invokes at runtime live in cli-tools.json so a
# skill can add one with a json-merge instead of editing this Dockerfile.
# install-cli-tools.sh installs each via pnpm (pinned), writing the per-tool
# only-built-dependencies opt-ins it reads from the manifest.
COPY cli-tools.json install-cli-tools.sh /tmp/
RUN --mount=type=cache,target=/root/.cache/pnpm \
    sh /tmp/install-cli-tools.sh /tmp/cli-tools.json

# ---- Notion CLI (official native release, checksum pinned) --------------------
ARG NOTION_CLI_VERSION=0.23.20
RUN set -eu; \
    case "$(uname -m)" in \
      x86_64) target=x86_64-unknown-linux-musl; checksum=fec196e491d4a6cd70ec3d43885526cc4444d5c6a9780a53ae536f83044250fa ;; \
      aarch64|arm64) target=aarch64-unknown-linux-musl; checksum=b86424b2411270e932e05f140322923e8250f70877e7d3ab247ea604fb1d5293 ;; \
      *) echo "Unsupported Notion CLI architecture" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://ntn.dev/releases/v${NOTION_CLI_VERSION}/ntn-${target}.tar.gz" -o /tmp/notion.tar.gz; \
    echo "${checksum}  /tmp/notion.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/notion.tar.gz -C /tmp; \
    mkdir -p /usr/local/lib/notion; \
    install -m 0755 "/tmp/ntn-${target}/ntn" /usr/local/lib/notion/ntn; \
    rm -rf /tmp/notion.tar.gz "/tmp/ntn-${target}"
COPY notion-cli/ntn /usr/local/bin/ntn

# ---- Python, uv, R, Quarto ---------------------------------------------------
# Python is Debian's python3 (3.11, externally managed — use `uv venv`, or
# `uv python install` for another version). R comes from CRAN's Debian repo
# because bookworm's own R is 4.2; the repo key is vendored next to this file
# (fingerprint 95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7). r-base-dev brings the
# compiler toolchain, so source builds work for both R and Python packages.
ARG R_VERSION=4.5.3-1~bookwormcran.0
COPY r-cran-debian.asc /etc/apt/keyrings/cran-debian.asc
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "deb [signed-by=/etc/apt/keyrings/cran-debian.asc] https://cloud.r-project.org/bin/linux/debian bookworm-cran40/" \
        > /etc/apt/sources.list.d/cran.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        r-base-core=${R_VERSION} \
        r-base-dev=${R_VERSION} \
        r-recommended=${R_VERSION} \
    && rm -rf /var/lib/apt/lists/*

ARG UV_VERSION=0.13.1
RUN set -eu; \
    case "$(uname -m)" in \
      x86_64) target=x86_64-unknown-linux-gnu; checksum=eadd9d27c134ab5ac1ffd4473b97a741407f3ea238288f03121fc4deddf90220 ;; \
      aarch64|arm64) target=aarch64-unknown-linux-gnu; checksum=9041c73c99fdc5892cf128140beb354eca9231d502068cc36e6cb53a8e59ad14 ;; \
      *) echo "Unsupported uv architecture" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${target}.tar.gz" -o /tmp/uv.tar.gz; \
    echo "${checksum}  /tmp/uv.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/uv.tar.gz -C /tmp; \
    install -m 0755 "/tmp/uv-${target}/uv" "/tmp/uv-${target}/uvx" /usr/local/bin/; \
    rm -rf /tmp/uv.tar.gz "/tmp/uv-${target}"

ARG QUARTO_VERSION=1.10.19
RUN set -eu; \
    case "$(uname -m)" in \
      x86_64) target=amd64; checksum=8e38c2b2df6a6dbd369ea16e15acded6894545258d13a02f777f81ad18fd7973 ;; \
      aarch64|arm64) target=arm64; checksum=bba2bb55add74c754c313905df42b0f45a8250aee2110a4fce7f83020bfe1b8f ;; \
      *) echo "Unsupported Quarto architecture" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${target}.tar.gz" -o /tmp/quarto.tar.gz; \
    echo "${checksum}  /tmp/quarto.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/quarto; \
    tar -xzf /tmp/quarto.tar.gz -C /opt/quarto --strip-components=1; \
    ln -s /opt/quarto/bin/quarto /usr/local/bin/quarto; \
    rm -f /tmp/quarto.tar.gz

# R installs from Posit Package Manager, which serves prebuilt Linux binaries
# (the user agent tells it which R to build for) — minutes of compiling become
# seconds of downloading. The baked packages come from a dated snapshot so a
# rebuild is reproducible; runtime installs track `latest`. renv is what the
# persistent cache serves; knitr + rmarkdown are what Quarto's R engine needs.
ARG R_PKG_SNAPSHOT=2026-10-01
RUN printf '%s\n' \
      'local({' \
      '  options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/bookworm/latest"))' \
      '  options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))' \
      '  options(Ncpus = max(1L, parallel::detectCores()))' \
      '})' >> /etc/R/Rprofile.site \
    && Rscript -e 'install.packages(c("renv", "knitr", "rmarkdown"), lib = "/usr/local/lib/R/site-library", repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/bookworm/'"${R_PKG_SNAPSHOT}"'"))' \
    && Rscript -e 'for (p in c("renv", "knitr", "rmarkdown")) library(p, character.only = TRUE)'

# Package caches. The host bind-mounts a persistent per-group dir over each
# (src/container-runner.ts, PACKAGE_CACHE_MOUNTS); they are pre-created here so
# the mount does not leave a root-owned ~/.cache behind. The cache sits on a
# different filesystem from the venv, so uv copies instead of warning that it
# cannot hardlink. R_LIBS_USER gives a plain install.packages() somewhere
# writable; it is per container — reuse across boots goes through renv.
ENV UV_CACHE_DIR=/home/node/.cache/uv \
    UV_LINK_MODE=copy \
    RENV_PATHS_CACHE=/home/node/.cache/R/renv \
    R_LIBS_USER=/home/node/.local/lib/R
RUN mkdir -p "$UV_CACHE_DIR" "$RENV_PATHS_CACHE" "$R_LIBS_USER" && \
    chmod -R 777 /home/node/.cache /home/node/.local

# ---- Exa Search (skill in container/skills/exa-search) ----------------------
# Non-secret marker; the credential gateway injects the real x-api-key for api.exa.ai.
ENV EXA_API_KEY=onecli-managed

# ---- ncl CLI wrapper ----------------------------------------------------------
# Actual script lives in the mounted source at /app/src/cli/ncl.ts.
RUN printf '#!/bin/sh\nexec bun /app/src/cli/ncl.ts "$@"\n' > /usr/local/bin/ncl && \
    chmod +x /usr/local/bin/ncl

# ---- Entrypoint --------------------------------------------------------------
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# ---- Workspace + permissions -------------------------------------------------
RUN mkdir -p /workspace/group /workspace/extra && \
    chown -R node:node /workspace && \
    chmod 777 /home/node

# Drop setuid-root from the binaries Debian ships (mount, su, passwd, ...). The
# agent runs unprivileged and needs none of them.
RUN find / -xdev -perm -4000 -type f -exec chmod u-s {} + || true

USER node
WORKDIR /workspace/group

# Only applies to a bare `docker run` — the host spawn overrides ENTRYPOINT and
# passes --init instead (see hardeningArgs in src/container-runner.ts).
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]

# ---- Provenance labels -------------------------------------------------------
# LAST on purpose. An ARG invalidates every layer below it, so declaring these
# up with the other build-args would make an otherwise-cached rebuild redo
# `bun install` and the pnpm global CLIs on every existing install, for two
# pieces of metadata. Labels have no filesystem effect, so they cost nothing here.
#
# Which lockfile the baked /app/node_modules came from: /app/src is mounted from
# the host checkout at every spawn, so an image and a checkout whose lockfiles
# disagree fail as a missing module inside a `--rm` container with no logs.
# container/pull.sh checks this before retagging. build.sh passes it; a bare
# `docker build` leaves it empty, which the pull path treats as unverifiable.
#
# image-source defaults to `local` so anything built from this file is honest
# unless its builder says otherwise — the retag cannot forge it after the fact.
ARG AGENT_RUNNER_LOCK_SHA256=
LABEL dev.nanoclaw.agent-runner-lock-sha256="${AGENT_RUNNER_LOCK_SHA256}"
ARG IMAGE_SOURCE=local
LABEL dev.nanoclaw.image-source="${IMAGE_SOURCE}"
