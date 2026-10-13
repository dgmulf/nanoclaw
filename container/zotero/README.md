# Zotero installation for this NanoClaw copy

The upstream `zotero-mcp-server==0.14.1` package supplies both `zotero-cli`
and `zotero-mcp`. The upstream skill and command reference from that package
are installed in `container/skills/zotero-cli/`.

The wrapper selects web mode, personal library `20217538`, and a non-secret
`onecli-managed` credential marker. OneCLI injects the existing Zotero vault
key into `Authorization: Bearer ...` for `api.zotero.org`. Agents must run
behind the configured gateway. Never replace the marker with a real key.

Install on the base image and any group-specific image in use:

```bash
bash container/zotero/install.sh
bash container/zotero/install.sh nanoclaw-agent-v2-207e7c29:ag-1791763628015-xfl6co
```

Reapply after pulling or rebuilding these images. The layer preserves the
published image and any group packages beneath it. New groups using the base
image inherit the CLI; groups selecting explicit skills must include
`zotero-cli`. The current group selects `all`.

Dependencies are pinned for Python 3.11 in `requirements.txt`. To update,
change `requirements.in`, resolve deliberately with `uv pip compile
--python-version 3.11`, then reinstall and validate the CLI.

Verification from an agent session:

```bash
zotero-cli --json config
zotero-cli --json get recent --limit 1
```

Semantic search and the optional PDF/scite extras are not installed.

To remove: delete `container/skills/zotero-cli` and `container/zotero`, then
restore/pull the base image and rebuild the group image using its unchanged
container configuration. Restart the affected groups. The Zotero vault entry
is pre-existing and should remain in OneCLI.
