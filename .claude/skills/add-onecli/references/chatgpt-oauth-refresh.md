# ChatGPT OAuth refresh with OneCLI

This fork backports [OneCLI #434](https://github.com/onecli/onecli/pull/434)
(commit `f8179ac80e003dacd16a0e4dfee2f0db330211bb`) to the pinned 1.42.0 gateway.
Stock 1.42.0 omits the required public Codex client ID on token refresh. The
fork image fixes that request and includes the upstream regression tests.

The `/add-onecli` setup automatically builds and applies the patch to supported
local Compose installations, including fresh deployments. For an existing
installation, run from the fork root:

```bash
pnpm exec tsx .claude/skills/add-onecli/scripts/local-gateway-patch.ts
```

See [build, validation and rollback](../../../../container/onecli-codex-routing/README.md).
Remote gateways need the same backport on their gateway host. Upgrading to
OneCLI 1.43+ remains unsupported because it removes the agent-grant API used
by this NanoClaw version.

A revoked or reused refresh token still requires the provider's sign-in recovery.
The container holds only a fixed non-secret sentinel. Token refresh and account
metadata remain gateway responsibilities; never copy live credentials into a group.
