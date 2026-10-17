#!/usr/bin/env bash
# Exercise the wiki agent's compute engines under production render restrictions.
# The temporary test project is never committed or published.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$project_root/setup/lib/install-slug.sh"
image=${1:-$(NANOCLAW_PROJECT_ROOT="$project_root" container_image_base):lab-wiki}
workspace=$(mktemp -d "$project_root/.tmp-wiki-execution.XXXXXXXX")
trap 'rm -rf -- "$workspace"' EXIT
mkdir "$workspace/source"
cat > "$workspace/source/_quarto.yml" <<'EOF'
project:
  type: website
execute:
  enabled: false
  echo: false
  error: false
EOF
cat > "$workspace/source/index.qmd" <<'EOF'
---
title: Python execution check
jupyter: python3
---

```{python}
import numpy as np
import pandas as pd
import scipy.stats as stats
import matplotlib.pyplot as plt
import seaborn as sns

values = pd.Series(np.arange(1, 5))
assert values.sum() == 10
assert stats.describe(values).nobs == 4
print("PYTHON_EXECUTION_" + "VERIFIED")
sns.lineplot(x=values.index, y=values)
plt.show()
```
EOF
cat > "$workspace/source/r.qmd" <<'EOF'
---
title: R execution check
engine: knitr
---

```{r}
library(knitr)
library(rmarkdown)
library(ggplot2)
library(dplyr)
library(tidyr)
library(readr)
library(reticulate)
values <- tibble(value = seq_len(4))
stopifnot(sum(values$value) == 10)
stopifnot(py_eval("sum(range(1, 5))") == 10)
cat(paste0("R_EXECUTION_", "VERIFIED"))
ggplot(values, aes(x = value, y = value^2)) + geom_line()
```
EOF
render() {
  docker run --rm --pull=never --network=none --user="$(id -u):$(id -g)" \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --memory=2g --cpus=2 --pids-limit=256 --read-only \
    --tmpfs=/tmp:rw,nosuid,nodev,size=512m \
    --mount="type=bind,src=$workspace,dst=/work" \
    --workdir=/work/source --env=HOME=/tmp --env=XDG_CACHE_HOME=/tmp/.cache \
    --entrypoint=quarto "$image" render . --execute --output-dir=../output
}
render 2>&1 | tee "$workspace/render.log"
if rg -q 'No such comm target registered: quarto_kernel_setup' "$workspace/render.log"; then
  echo 'ERROR: standard Python kernel received an unsupported Quarto setup message' >&2
  exit 1
fi
rg -q PYTHON_EXECUTION_VERIFIED "$workspace/output/index.html"
rg -q R_EXECUTION_VERIFIED "$workspace/output/r.html"
test -n "$(find "$workspace/output/index_files" -name '*.png' -print -quit)"
test -n "$(find "$workspace/output/r_files" -name '*.png' -print -quit)"

# Python exceptions must remain visible and reject validation.
cp "$workspace/source/index.qmd" "$workspace/python-original.qmd"
cat >> "$workspace/source/index.qmd" <<'EOF'

```{python}
raise RuntimeError("EXPECTED_WIKI_PYTHON_FAILURE")
```
EOF
if render > "$workspace/python-failure.log" 2>&1; then
  echo 'ERROR: rendering a failing Python cell unexpectedly succeeded' >&2
  exit 1
fi
rg -q 'RuntimeError.*EXPECTED_WIKI_PYTHON_FAILURE' "$workspace/python-failure.log"
mv "$workspace/python-original.qmd" "$workspace/source/index.qmd"

# A failing R cell must also reject validation.
cat >> "$workspace/source/r.qmd" <<'EOF'

```{r}
stop("EXPECTED_WIKI_VALIDATION_FAILURE")
```
EOF
if render > "$workspace/expected-failure.log" 2>&1; then
  echo 'ERROR: rendering a failing R cell unexpectedly succeeded' >&2
  exit 1
fi
rg -q EXPECTED_WIKI_VALIDATION_FAILURE "$workspace/expected-failure.log"
echo 'PASS: clean Python setup, offline Python/R, reticulate, plots, and Python/R error reporting'
