---
name: lab-wiki
description: Develop and publish updates to the user's Quarto research wiki, including hypotheses, experiments, and academic literature.
---

# Lab Wiki

The wiki is a static Quarto website. Its canonical source is the host bare Git
repository `/srv/wiki/source.git`, branch `main`. The private live site is
https://clamber.exe.xyz:8080/.

## Access and workspace

The operator grants Lab a restricted SSH signing socket and public configuration.
No private key is needed inside the container. For Git operations set:

```sh
export GIT_SSH_COMMAND='ssh -F /workspace/extra/wiki-ssh/config'
```

Remote: `lab-wiki:/srv/wiki/source.git`. Clone into a fresh task-specific directory
under `/workspace/agent/wiki-work/` so concurrent sessions cannot overwrite each
other's changes. Use `git clone --branch main` and configure a local commit identity
if needed (`Lab Agent`, `lab-agent@localhost`). The remote is Git-only; shell and
forwarding requests are intentionally rejected. If the socket/config is missing,
report the missing access; do not invent credentials or use another remote.

Quarto 1.10.19 matches production. Use `quarto-authoring` for Quarto syntax and
`uv` for Python projects. `UV_CACHE_DIR=/workspace/agent/.cache/uv` is already
host-persistent across container restarts. Keep Python environments out of Git.

## Update and publish

A user request to update the wiki authorizes the following check/render/push
workflow. A draft or preview request stops before pushing.

1. Fetch current `main`, inspect the project and its existing conventions, and
   make the requested changes. Distinguish hypotheses from findings; cite sources
   and preserve experiment provenance. Never invent results or bibliographic data.
2. Run project-defined checks and relevant experiment tests. For an existing uv
   project use its committed lockfile (`uv sync --locked`). Experiments run locally:
   the production renderer has **no network or Python/R environment and disables
   code execution**. Commit precomputed results and local assets needed by pages.
3. Review `git diff --check`, the source diff, and exactly which files will be
   committed. Exclude `.venv`, caches, secrets, and generated site output. Commit
   only the requested source/assets. Fetch again and rebase onto `origin/main`
   if needed; resolve conflicts deliberately and repeat checks after any change.
4. Validate the exact commit to publish: export `HEAD` with `git archive` into a
   fresh temporary `source` directory (outside the working checkout), then run
   `quarto render . --no-execute --output-dir=../output` from that source directory.
   This prevents untracked files or cached renders from masking missing assets.
   Require a successful render, `output/index.html`, and no symlinks or special
   files in output. Inspect relevant rendered pages, links, citations, and warnings.
   Keep the staging output outside Git. Run checks again on the exported source
   when they depend on committed files.
5. Only after checks and staging validation succeed, push the validated commit
   with `git push origin HEAD:main`. Never force-push. If rejected because another
   author updated main, fetch/rebase and repeat checks and the clean staging render
   before retrying; stop and report if conflicts or repeated contention prevent
   a safe update. Never publish after a failed check or render.

The host renders asynchronously and atomically activates successful output.
Report the pushed commit and validation results; **push accepted does not mean
deployment succeeded**. Verify the changed live page if accessible; otherwise say
publication is queued/unverified. Browser access may require the user's exe.dev
session. Do not attempt SSH shell commands to read host deployment files.
