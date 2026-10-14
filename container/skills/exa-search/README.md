# Exa Search skill

`SKILL.md` and `LICENSE` are copied unchanged from https://github.com/exa-labs/agent-skills
(`skills/exa-search/`) at commit `5c3fd25c258a34cfaad196fecb1b135a2dc7fa87`.
`instructions.md` is local: it explains the gateway setup.

The agent image sets `EXA_API_KEY=onecli-managed`, a non-secret marker. OneCLI holds
the real key as the generic secret "Exa API Key" (host `api.exa.ai`, header `x-api-key`)
and injects it for the agents it is assigned to (Nano, Lab).

To update, re-copy `SKILL.md` from upstream and bump the commit above. To remove,
delete this directory and the `EXA_API_KEY` line in `container/Dockerfile`, remove the
gateway secret, and rebuild the image.
