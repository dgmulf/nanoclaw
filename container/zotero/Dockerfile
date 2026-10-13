ARG BASE_IMAGE=nanoclaw-zotero-base:latest
FROM ${BASE_IMAGE}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/zotero-requirements.txt
RUN python3 -m venv /opt/zotero \
    && /opt/zotero/bin/pip install --no-cache-dir -r /tmp/zotero-requirements.txt \
    && /opt/zotero/bin/pip check \
    && rm /tmp/zotero-requirements.txt
COPY zotero-wrapper.sh /usr/local/bin/zotero-cli
RUN chmod 755 /usr/local/bin/zotero-cli \
    && ln -sf /usr/local/bin/zotero-cli /usr/local/bin/zotero-mcp
LABEL dev.nanoclaw.zotero-version="0.14.1"
USER node
