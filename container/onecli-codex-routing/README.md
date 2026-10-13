# OneCLI 1.42.0 Codex workspace compatibility

Backports the account-ID fix described in
https://github.com/onecli/onecli/pull/578 to the installed, pinned gateway.
Codex >=0.156 validates its selected account against routing discovery;
`onecli-managed` is not a real account ID.

The derived image uses only existing `metadata.accountId`, preserves all token
placeholders, and omits the previously fabricated `free` plan when the account
is known. It does not read decrypted credentials or change gateway policy.
Unexpected bundle layouts fail the build.

Build: `docker build -t onecli-nanoclaw-codex:1.42.0 container/onecli-codex-routing`

Deploy by replacing only the `onecli` service's image in the existing Compose
file. Preserve its environment, volumes, and database. Roll back by restoring
`ghcr.io/onecli/onecli:${ONECLI_VERSION:-latest}` and recreating that service.
Gateway setup or upgrades can restore the stock image; reapply this patch until
the upstream fix is included in a supported gateway release.
