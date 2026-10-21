# ruff skill

`SKILL.md`, `LICENSE-MIT` and `LICENSE-APACHE` are copied unchanged from
https://github.com/astral-sh/claude-code-plugins (`plugins/astral/skills/ruff/`) at commit
`f3ce88a7ba830f53afd6d944c1d0278ed318e142`.

ruff is not baked into the agent image; agents run it with `uvx ruff` (or `uv run ruff`
in projects that pin it), using the `uv` binary from the image and the per-agent-group
uv cache.

To update, re-copy `SKILL.md` from upstream and bump the commit above. To remove,
delete this directory.
