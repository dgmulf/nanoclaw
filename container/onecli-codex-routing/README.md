# Fork-owned OneCLI 1.42.0 backports

This image retains the supported gateway API and database schema while applying:

- Account-ID routing from [OneCLI #578](https://github.com/onecli/onecli/pull/578).
  Codex >=0.156 validates its account against routing discovery. The web patch
  uses existing `metadata.accountId`; all credential placeholders stay fixed.
- ChatGPT OAuth refresh from [OneCLI #434](https://github.com/onecli/onecli/pull/434),
  upstream commit `f8179ac80e003dacd16a0e4dfee2f0db330211bb`. The unchanged upstream
  diff, including its three regression tests, is in `openai-refresh.patch`.
  It adds the public Codex `client_id` to the refresh grant. Only the gateway
  reads, rotates and persists tokens; credentials never enter agent containers.

The Dockerfile pins the 1.42.0 source commit and archive checksum, Rust builder
image digest, upstream runtime image digest and Cargo lockfile. It applies the
patch without fuzz, runs the Rust unit suite, and replaces only the gateway
binary plus the previously patched web stub generator. No database migration,
secret reassignment or newer OneCLI release is involved. Unexpected source or
bundle layouts fail the build. The initial build can take several minutes.

## Automatic deployment

This fork's `/add-onecli` setup calls
`.claude/skills/add-onecli/scripts/local-gateway-patch.ts` for fresh installs and
reuse of a supported local Compose gateway. It builds the image before changing
Compose, backs up Compose privately, changes only the `onecli` image, starts only
that service and checks both gateway and web health. Failure restores the old
Compose configuration and service. PostgreSQL, volumes, credentials, ports and
environment settings are preserved. Repeating setup on a patched install skips
the build and restart.

A remote gateway must run this procedure on its own host. Setup does not replace
an unrelated gateway, a source-built service or an unsupported gateway version.

To apply to an existing local installation directly, from this fork's root:

```bash
pnpm exec tsx .claude/skills/add-onecli/scripts/local-gateway-patch.ts
```

Manual build (the setup helper uses this same command):

```bash
docker build -t onecli-nanoclaw-codex:1.42.0-refresh1 container/onecli-codex-routing
```

## Validation and rollback

The build runs the upstream Rust unit suite, including the refresh-form,
public-client-ID and endpoint regression tests. Setup behavior is covered by
`local-gateway-patch.test.ts` (fresh install, existing routing patch, idempotence,
external gateway, unsupported version, failed build, failed health and rollback).
Routing tests use the original pinned web bundle:

```bash
ONECLI_TEST_BUNDLE=/path/to/original-bundle.js node --test container/onecli-codex-routing/patch.test.cjs
```

After deployment, make a credentialed read through the gateway and check that
refresh succeeds. A revoked or already-reused refresh token still requires
sign-in. Do not log token values. Health alone does not prove OAuth works.

To roll back, restore the Compose backup printed by its filename beside
`~/.onecli/docker-compose.yml`, then run `docker compose up -d --no-deps --pull
never onecli` in that directory. Old images remain available; do not delete
vault volumes or encryption keys. Rolling back reintroduces the refresh bug.
