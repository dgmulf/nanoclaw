#!/usr/bin/env bash
# Operator smoke test; never changes remote refs or publishes content.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$project_root/setup/lib/install-slug.sh"
image="$(NANOCLAW_PROJECT_ROOT="$project_root" container_image_base):lab-wiki"
base_image="$(NANOCLAW_PROJECT_ROOT="$project_root" container_image_base):latest"
docker run --rm --network=none --entrypoint sh "$base_image" -c '
  set -eu
  for tool in ssh python3 gcc R Rscript quarto uv; do
    if command -v "$tool"; then
      echo "ERROR: Lab-only tool $tool leaked into the standard base image" >&2
      exit 1
    fi
  done
  echo "PASS: standard base excludes Lab-only tools"
'
bash "$project_root/scripts/wiki/check-execution.sh" "$image"
work=$(mktemp -d "$project_root/.tmp-wiki-check.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
docker run --rm --user "$(id -u):$(id -g)" \
  --add-host=host.docker.internal:host-gateway \
  --mount "type=bind,src=$work,dst=/workspace/agent" \
  --mount type=bind,src=/run/wiki-lab-agent,dst=/workspace/extra/wiki-ssh,readonly \
  --workdir /workspace/agent --entrypoint bash "$image" -lc '
    set -euo pipefail
    test "$(quarto --version)" = 1.10.19
    test "$(uv cache dir)" = /workspace/agent/.cache/uv
    mkdir -p "$UV_CACHE_DIR"
    printf persisted > "$UV_CACHE_DIR/wiki-smoke-marker"
    uv venv /tmp/wiki-venv
    /tmp/wiki-venv/bin/python -c "assert 2+2 == 4"
    export GIT_SSH_COMMAND="ssh -F /workspace/extra/wiki-ssh/config"
    git clone --branch main lab-wiki:/srv/wiki/source.git checkout
    cd checkout
    git diff --check
    mkdir ../source
    git archive HEAD | tar -xf - -C ../source
  '
# Execute the exported site separately, without the Git authentication socket,
# using the same network, filesystem, and resource restrictions as production.
docker run --rm --network=none --user="$(id -u):$(id -g)" \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --memory=2g --cpus=2 --pids-limit=256 --read-only \
  --tmpfs=/tmp:rw,nosuid,nodev,size=512m \
  --mount="type=bind,src=$work,dst=/work" \
  --workdir=/work/source --env=HOME=/tmp --env=XDG_CACHE_HOME=/tmp/.cache \
  --entrypoint=quarto "$image" render . --execute --output-dir=../output
test -f "$work/output/index.html"
test -z "$(find "$work/output" -mindepth 1 ! -type f ! -type d -print -quit)"
docker run --rm --user "$(id -u):$(id -g)" \
  --add-host=host.docker.internal:host-gateway \
  --mount "type=bind,src=$work,dst=/workspace/agent" \
  --mount type=bind,src=/run/wiki-lab-agent,dst=/workspace/extra/wiki-ssh,readonly \
  --workdir /workspace/agent/checkout --entrypoint bash "$image" -lc '
    set -euo pipefail
    export GIT_SSH_COMMAND="ssh -F /workspace/extra/wiki-ssh/config"
    git push --dry-run origin HEAD:main
    if ssh -F /workspace/extra/wiki-ssh/config lab-wiki id; then
      echo "ERROR: host shell access was allowed" >&2; exit 1
    fi
    if git ls-remote lab-wiki:/etc; then
      echo "ERROR: unrelated repository access was allowed" >&2; exit 1
    fi
  '
docker run --rm --network=none --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$work,dst=/workspace/agent" \
  --workdir /workspace/agent --entrypoint bash "$image" -lc '
    set -eu
    test "$(cat "$UV_CACHE_DIR/wiki-smoke-marker")" = persisted
    echo "PASS: tools, clean render, Git authorization, SSH restrictions, persistent uv cache"
  '
