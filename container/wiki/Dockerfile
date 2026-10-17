# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e
# Opt-in Lab runtime. Build with scripts/wiki/build-image.sh.
# The helper resolves the installed base to an image ID and provides an
# ID-specific local tag so BuildKit never treats a config digest as a registry
# manifest digest. Normal agents keep their original base image.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-client \
        python3 \
        python3-dev \
        python3-venv \
        python3-ipykernel \
        python3-nbclient \
        python3-nbformat \
        python3-yaml \
        python3-numpy \
        python3-pandas \
        python3-matplotlib \
        python3-scipy \
        python3-seaborn \
        r-base-core \
        r-base-dev \
        r-cran-knitr \
        r-cran-rmarkdown \
        r-cran-ggplot2 \
        r-cran-dplyr \
        r-cran-tidyr \
        r-cran-readr \
        r-cran-reticulate \
        build-essential \
    && dpkg-query -W > /opt/wiki-agent-packages.txt \
    && rm -rf /var/lib/apt/lists/*

# Match production's execution capabilities. Debian and production's Ubuntu
# provide different Python/R package versions; the manifest records this image.
ENV QUARTO_PYTHON=/usr/bin/python3 \
    RETICULATE_PYTHON=/usr/bin/python3 \
    MPLBACKEND=Agg \
    MPLCONFIGDIR=/tmp/matplotlib \
    JUPYTER_PLATFORM_DIRS=1 \
    OPENBLAS_NUM_THREADS=1 \
    OMP_NUM_THREADS=1

# ---- Wiki authoring + Python environments -----------------------------------
# Match the wiki server renderer. Checksums are the sha256 digests published
# on the official quarto-dev/quarto-cli and astral-sh/uv GitHub releases.
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
    rm /tmp/quarto.tar.gz

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

# The group workspace is host-persistent. Copy instead of hardlinking packages
# between its cache and environments on other mounts.
ENV UV_CACHE_DIR=/workspace/agent/.cache/uv
ENV UV_LINK_MODE=copy

# Keep standard ipykernel's normal setup cells, without sending it the optional
# custom-kernel comm handshake it does not implement. Hash-guarded for 1.10.19.
COPY patch-quarto-jupyter.py /tmp/patch-quarto-jupyter.py
RUN /usr/bin/python3 /tmp/patch-quarto-jupyter.py && rm /tmp/patch-quarto-jupyter.py

# Apt packages may introduce privileged executables; retain base hardening.
RUN find / -xdev -perm -4000 -type f -exec chmod u-s {} +
USER node

# Inherit entrypoint, workdir and lockfile provenance from the exact base.
ARG BASE_IMAGE_ID
LABEL dev.nanoclaw.derived-from="${BASE_IMAGE_ID}"
LABEL dev.nanoclaw.image-source="derived"
