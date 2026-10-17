#!/usr/bin/env bash
# Build only the opt-in wiki runtime; never change group configuration.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$project_root/setup/lib/install-slug.sh"
runtime=${CONTAINER_RUNTIME:-docker}
image_name=$(NANOCLAW_PROJECT_ROOT="$project_root" container_image_base)
base_image="${image_name}:latest"
wiki_image="${image_name}:lab-wiki"
if [[ $# -ne 0 ]]; then
  echo 'Usage: bash scripts/wiki/build-image.sh' >&2
  exit 2
fi
base_id=$("$runtime" image inspect --format '{{.Id}}' "$base_image")
[[ $base_id =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid base image ID.' >&2; exit 1; }
# BuildKit needs a named local image reference. Never derive from the mutable
# latest tag: snapshot its inspected ID under a content-specific reference.
pinned_base="${image_name}:wiki-base-${base_id#sha256:}"
"$runtime" image tag "$base_id" "$pinned_base"
[[ $("$runtime" image inspect --format '{{.Id}}' "$pinned_base") == "$base_id" ]]
printf 'Building %s from %s\n' "$wiki_image" "$base_id"
"$runtime" build --pull=false \
  --file "$project_root/container/wiki/Dockerfile" \
  --build-arg "BASE_IMAGE=$pinned_base" \
  --build-arg "BASE_IMAGE_ID=$base_id" \
  --tag "$wiki_image" "$project_root/container/wiki"
[[ $("$runtime" image inspect --format '{{.Id}}' "$pinned_base") == "$base_id" ]]
[[ $("$runtime" image inspect --format '{{index .Config.Labels "dev.nanoclaw.derived-from"}}' "$wiki_image") == "$base_id" ]]
printf 'Built %s. Assign it only to the intended group.\n' "$wiki_image"
