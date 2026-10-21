# ty skill

`SKILL.md`, `LICENSE-MIT` and `LICENSE-APACHE` are copied unchanged from
https://github.com/astral-sh/claude-code-plugins (`plugins/astral/skills/ty/`) at commit
`f3ce88a7ba830f53afd6d944c1d0278ed318e142`.

ty is not baked into the agent image; agents run it with `uvx ty` (or `uv run ty` in
projects that pin it), using the `uv` binary from the image and the per-agent-group uv
cache. The "Language server" section refers to the upstream plugin's LSP config, which
is not installed here — agents get the `ty check` CLI only.

To update, re-copy `SKILL.md` from upstream and bump the commit above. To remove,
delete this directory.
