---
name: lab-wiki
description: Validate, stage, and publish updates to the Quarto wiki through its restricted SSH Git endpoint.
---

# Lab Wiki

The wiki is a static Quarto website. Its canonical source is the host bare Git
repository `/srv/wiki/source.git`, branch `main`. The private live site is
https://clamber.exe.xyz:8080/.

## Access and workspace

Authenticate through the host-managed SSH signing socket and mounted public SSH
configuration. The private key stays on the host; the SSH endpoint permits only
Git access to the wiki repository. For Git operations set:

```sh
export GIT_SSH_COMMAND='ssh -F /workspace/extra/wiki-ssh/config'
```

Remote: `lab-wiki:/srv/wiki/source.git`. Clone into a fresh task-specific directory
under `/workspace/agent/wiki-work/` so concurrent sessions cannot overwrite each
other's changes. Use `git clone --branch main` and configure a repository-local
commit identity if one is not already configured. The remote is Git-only; shell and
forwarding requests are intentionally rejected. If the socket/config is missing,
report the missing access; do not invent credentials or use another remote.

Quarto 1.10.19 matches production. Both environments include Python/Jupyter with
NumPy, pandas, SciPy, Matplotlib, and seaborn, plus R/knitr with rmarkdown,
ggplot2, dplyr, tidyr, readr, and reticulate. Python pages use `jupyter: python3`;
R pages use `engine: knitr`. `QUARTO_PYTHON` and `RETICULATE_PYTHON` select the
system Python at `/usr/bin/python3`, including for Python called from R.

The agent image uses Debian and production uses Ubuntu, so runtime and package
versions can differ. Use dependencies available in production; installing a
package locally does not add it to the renderer. New production dependencies
require an operator image update before publishing code that needs them.
`UV_CACHE_DIR=/workspace/agent/.cache/uv` is host-persistent across container
restarts. Keep Python environments and generated R session state out of Git.

## Update and publish

A user request to update the wiki authorizes the following check/render/push
workflow. A draft or preview request stops before pushing.

1. Fetch current `main` and make the requested changes.
2. Run project-defined checks and tests. Production **executes Python and R code
   during rendering without network access**. Commit input data and local assets
   needed by code cells; do not download data or install packages at render time.
   Use `eval: false` on cells that should not execute. The host passes `--execute`,
   which enables execution even if project-level execution is disabled.
3. Review `git diff --check`, the source diff, and exactly which files will be
   committed. Exclude `.venv`, caches, `.RData`, `.Rhistory`, secrets, and generated
   site output. Commit only the requested source/assets. Fetch again and rebase
   onto `origin/main` if needed; resolve conflicts deliberately and repeat checks
   after any change.
4. Validate the exact commit to publish: export `HEAD` with `git archive` into a
   fresh temporary `source` directory (outside the working checkout), then run
   `quarto render . --execute --output-dir=../output` from that source directory.
   This prevents untracked files or cached renders from masking missing assets.
   Require a successful render, `output/index.html`, and no symlinks or special
   files in output. Inspect relevant rendered pages, links, assets, and warnings.
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
