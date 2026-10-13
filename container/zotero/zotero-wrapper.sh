#!/bin/sh
# Only a placeholder reaches the agent; OneCLI injects the real credential.
export ZOTERO_LOCAL=false
export ZOTERO_API_KEY=onecli-managed
export ZOTERO_LIBRARY_ID="${ZOTERO_LIBRARY_ID:-20217538}"
export ZOTERO_LIBRARY_TYPE="${ZOTERO_LIBRARY_TYPE:-user}"
# requests (PDF downloads) and httpx (API calls) both trust the gateway CA.
if [ -n "${SSL_CERT_FILE:-}" ]; then
    export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
fi
exec "/opt/zotero/bin/$(basename "$0")" "$@"
