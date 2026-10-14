# Notion CLI

The image installs the official native Notion CLI 0.23.20 from https://ntn.dev,
with SHA-256 pins for Linux x64 and arm64. The `ntn` wrapper supplies only a
non-secret marker; OneCLI injects `Authorization: Bearer <token>` for the exact
host `api.notion.com`. Store the token in the gateway and assign it to the
intended groups, preserving their existing assignments.

The official skill and license in `container/skills/notion-cli/` are copied
unchanged from https://github.com/makenotion/skills at commit
`10e976aa591995fd60c75ef13beba1a8aa827fcc`. The adjacent `instructions.md` explains
the local gateway setup and overrides the skill's interactive login guidance.

To update, verify both release checksums and update the Dockerfile version and
pins together, then rebuild the base image and any per-group derived images.
To remove, delete the Notion Dockerfile block and these two directories, remove
the gateway assignments/secret if no longer needed, and rebuild the images.
