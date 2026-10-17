# Lab wiki Git transport

## Agent installation

The separate `container/wiki/Dockerfile` installs Quarto **1.10.19** (matching the server),
uv/uvx **0.13.1**, Python and build tools, and OpenSSH. Release archives are
checksum-pinned for amd64 and arm64. The standard base image has none of these
wiki-specific additions. Build the base with `./container/build.sh`, then build
the derived Lab image with `bash scripts/wiki/build-image.sh`.
`UV_CACHE_DIR=/workspace/agent/.cache/uv` uses the existing persistent group
mount; `UV_LINK_MODE=copy` supports environments on other mounts.

The complete upstream `quarto-authoring` and `uv` skills are vendored under
`scripts/wiki/skills/`, with revision/license information in each `UPSTREAM.json`.
Copy both directories into Lab's private
`data/v2-sessions/<group-id>/.claude-shared/skills/` store so other agents are not
instructed to use the Lab-only tools.
The private publishing skill is `scripts/wiki/lab-wiki/SKILL.md`. Install it into
`data/v2-sessions/<group-id>/.claude-shared/skills/lab-wiki/SKILL.md`; NanoClaw's
provider-neutral materializer exposes it on the next container spawn. For this
install, Lab's ID is `ag-1791873957319-1uniyl`.

Use `/manage-mounts` to allowlist `/run/wiki-lab-agent` read-only, preserving any
existing roots, then configure Lab:

```sh
bin/ncl groups config add-mount --id ag-1791873957319-1uniyl \
  --host /run/wiki-lab-agent --container wiki-ssh --ro
bin/ncl groups config update --id ag-1791873957319-1uniyl \
  --image-tag nanoclaw-agent-v2-207e7c29:lab-wiki
bin/ncl groups restart --id ag-1791873957319-1uniyl
```

The CLI container path is relative to `/workspace/extra`. Only Lab receives the
wiki image, signing socket, and all three wiki skills. The image prefix above is
specific to this installation; the build helper prints the correct tag for its
checkout. After updating the base image, rebuild the derived image and restart
Lab. `ncl groups restart --rebuild` uses the generic package-image builder and
would replace Lab's custom image selection: use the wiki build helper followed by
`ncl groups restart` without `--rebuild` instead. Existing custom images and
package selections for other groups are independent and remain unchanged.

## Host transport

`sudo bash scripts/wiki/install-transport.sh` installs a separate systemd-managed
sshd bound to the Docker default bridge gateway on port 2222. It uses the existing
`exedev` account (uid 1000), which owns `/srv/wiki/source.git`. It does not modify
the primary SSH daemon or its authorized keys. Install host `openssh-server` and
`openssh-client` first if absent.

Only the dedicated public key is accepted. Passwords, shells, PTYs, forwarding,
user SSH rc scripts, and every command except the two exact Git service commands
for `/srv/wiki/source.git` are rejected. Existing repository hooks still execute
under the repository owner's account as part of normal Git receive behavior.
The private client and dedicated server host keys live under root-only
`/etc/wiki-lab-ssh`. No private key is mounted into an agent container.
PAM performs account checks so the host's password-locked account can still use
public-key authentication; password and keyboard-interactive login remain disabled.

The signing agent runs as uid 1000. A root service step loads the private key;
only the Unix socket and public client configuration appear under
`/run/wiki-lab-agent`. Both services start on boot and recreate runtime files.
This is a local restricted SSH transport; the selected HTTPS credential gateway
and its approval rules are unchanged.

Mount `/run/wiki-lab-agent` read-only at `/workspace/extra/wiki-ssh` **for Lab only**.
Use the standard Docker `host.docker.internal` host-gateway alias. The container
must resolve it to the same Docker bridge address printed by the installer.

```sh
export GIT_SSH_COMMAND='ssh -F /workspace/extra/wiki-ssh/config'
git ls-remote lab-wiki:/srv/wiki/source.git
git clone lab-wiki:/srv/wiki/source.git wiki
```

The config pins the dedicated host public key without trust-on-first-use and
selects only the public identity backed by the signing socket. Sharing that
socket grants wiki Git read/write access, so do not mount it into other groups.
Root on the host and the host `exedev` account remain trusted. A container can
ask the agent to sign but cannot export its private key.

Validate after installation: `systemctl is-active wiki-lab-agent wiki-lab-sshd`,
then run `git ls-remote` in Lab. Verify shell commands and another repository
path fail. Reboot verification should confirm both services and public runtime
files return. If the Docker default bridge gateway changes, rerun the installer.
Run `bash scripts/wiki/check-container.sh` for a repeatable container smoke test:
base-image tool exclusion, Lab tool versions, a clean committed-source render,
dry-run push, rejected shell/other-repo
requests, and uv cache persistence across container recreation. It never changes
remote refs.
It preserves the existing key pair and regenerates the pinned public config.
The installer restarts both dedicated services. The signing runtime directory is
preserved across restarts, keeping existing container bind mounts attached while
the socket is recreated. New Git operations reconnect through the new socket.
An operation in flight during a restart may fail and need retrying.

## Removal

First remove Lab's extra mount and Git SSH configuration, then stop its running
container so no client retains the signing socket. On the host run:

```sh
sudo systemctl disable --now wiki-lab-sshd.service wiki-lab-agent.service
sudo rm -f /etc/systemd/system/wiki-lab-sshd.service /etc/systemd/system/wiki-lab-agent.service
sudo rm -f /etc/wiki-lab-authorized-keys
sudo rm -f /usr/local/libexec/wiki-lab-git
sudo rm -rf /etc/wiki-lab-ssh /run/wiki-lab-agent
sudo systemctl daemon-reload
```

Removal deletes only this dedicated transport and its keys. The repository,
wiki deploy service, primary sshd, and HTTPS gateway remain installed.
Remove its allowlist entry, Lab's three private wiki skills from both the canonical
store and provider materialization, and any wiki checkouts only if no unpublished
work remains. To remove the development tools too, clear Lab's `--image-tag` to
use the base image, respawn Lab, then remove its unused `:lab-wiki` image. No base
image changes are needed. Persistent uv caches may
be removed independently after stopping processes using them.
