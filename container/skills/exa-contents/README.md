# Exa Contents skill

`SKILL.md` and `LICENSE` are copied unchanged from https://github.com/exa-labs/agent-skills
(`skills/exa-contents/`) at commit `5c3fd25c258a34cfaad196fecb1b135a2dc7fa87`.
`instructions.md` is local: it explains the gateway setup.

Authentication is shared with `exa-search`: the image's `EXA_API_KEY=onecli-managed`
marker plus the OneCLI generic secret "Exa API Key" (host `api.exa.ai`, header
`x-api-key`), assigned to Nano and Lab. See `../exa-search/README.md`.

To update, re-copy `SKILL.md` from upstream and bump the commit above. To remove,
delete this directory; leave the marker and secret in place while `exa-search` uses them.
