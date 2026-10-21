# uv skill

`SKILL.md`, `LICENSE-MIT` and `LICENSE-APACHE` are copied unchanged from
https://github.com/astral-sh/claude-code-plugins (`plugins/astral/skills/uv/`) at commit
`f3ce88a7ba830f53afd6d944c1d0278ed318e142`.

The `uv` binary itself ships in the agent image (see `container/Dockerfile`), and the
host mounts a per-agent-group uv cache, so no extra setup is needed.

To update, re-copy `SKILL.md` from upstream and bump the commit above. To remove,
delete this directory.
