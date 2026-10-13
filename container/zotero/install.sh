#!/bin/bash
# Reapply after pulling/rebuilding the base image or rebuilding group images.
set -euo pipefail
ZOTERO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ZOTERO_DIR/../.." && pwd)"
source "$PROJECT_ROOT/setup/lib/install-slug.sh"
ZOTERO_IMAGE_BASE="$(container_image_base)"
if [ "$#" -eq 0 ]; then
    set -- "$ZOTERO_IMAGE_BASE:latest"
fi
for ZOTERO_IMAGE in "$@"; do
    ZOTERO_BASE_ID="$(docker image inspect --format '{{.Id}}' "$ZOTERO_IMAGE")"
    ZOTERO_BASE_TAG="$ZOTERO_IMAGE_BASE:zotero-base-${ZOTERO_BASE_ID:7:12}"
    docker tag "$ZOTERO_BASE_ID" "$ZOTERO_BASE_TAG"
    docker build --build-arg "BASE_IMAGE=$ZOTERO_BASE_TAG" \
        -t "$ZOTERO_IMAGE" "$ZOTERO_DIR"
    docker run --rm --network none --entrypoint zotero-cli "$ZOTERO_IMAGE" --json config
done
