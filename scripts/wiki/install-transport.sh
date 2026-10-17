#!/bin/bash
# Operator-run local transport for Lab. Does not change the primary sshd.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this installer as root.' >&2; exit 1; }
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly transport_dir=/etc/wiki-lab-ssh
readonly runtime_dir=/run/wiki-lab-agent
readonly git_user=exedev
readonly port=2222
[[ $(id -u "$git_user") == 1000 ]] || { echo 'Expected exedev uid 1000.' >&2; exit 1; }
[[ -d /srv/wiki/source.git ]] || { echo 'Wiki bare repository missing.' >&2; exit 1; }
for command in sshd ssh-agent ssh-add ssh-keygen docker systemctl python3; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
bridge_ip=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')
python3 - "$bridge_ip" <<'PY'
import ipaddress, sys
address = ipaddress.ip_address(sys.argv[1])
if address.version != 4 or not address.is_private or address.is_loopback or address.is_unspecified:
    raise SystemExit('Expected a private Docker bridge IPv4 gateway')
PY
install -d -o root -g root -m 0700 "$transport_dir"
install -d -o root -g root -m 0755 /run/sshd
install -d -o root -g root -m 0755 /usr/local/libexec
install -o root -g root -m 0755 "$source_dir/forced-git-command" /usr/local/libexec/wiki-lab-git
if [[ ! -f $transport_dir/id_ed25519 ]]; then
  ssh-keygen -q -t ed25519 -N '' -C wiki-lab-only -f "$transport_dir/id_ed25519"
fi
if [[ ! -f $transport_dir/ssh_host_ed25519_key ]]; then
  ssh-keygen -q -t ed25519 -N '' -C wiki-lab-host -f "$transport_dir/ssh_host_ed25519_key"
fi
chmod 0600 "$transport_dir/id_ed25519" "$transport_dir/ssh_host_ed25519_key"
printf 'restrict %s\n' "$(cat "$transport_dir/id_ed25519.pub")" > "$transport_dir/authorized_keys"
chmod 0600 "$transport_dir/authorized_keys"
cat > "$transport_dir/sshd_config" <<EOF
Port $port
ListenAddress $bridge_ip
AddressFamily inet
HostKey $transport_dir/ssh_host_ed25519_key
PidFile /run/wiki-lab-sshd.pid
AuthorizedKeysFile $transport_dir/authorized_keys
StrictModes yes
AllowUsers $git_user
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
UsePAM yes
PermitRootLogin no
AllowAgentForwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
PermitTTY no
X11Forwarding no
PermitUserEnvironment no
PermitUserRC no
MaxSessions 4
LogLevel VERBOSE
ForceCommand /usr/local/libexec/wiki-lab-git
EOF
# sshd must read authorized_keys after switching to the account uid. Keep the
# secret directory inaccessible, and expose only its non-secret key allowlist.
install -o root -g root -m 0644 "$transport_dir/authorized_keys" /etc/wiki-lab-authorized-keys
sed -i 's|^AuthorizedKeysFile .*|AuthorizedKeysFile /etc/wiki-lab-authorized-keys|' "$transport_dir/sshd_config"
cat > "$transport_dir/config" <<'EOF'
Host lab-wiki
    HostName host.docker.internal
    Port 2222
    User exedev
    IdentityAgent /workspace/extra/wiki-ssh/agent.sock
    IdentityFile /workspace/extra/wiki-ssh/id_ed25519.pub
    IdentitiesOnly yes
    UserKnownHostsFile /workspace/extra/wiki-ssh/known_hosts
    StrictHostKeyChecking yes
    BatchMode yes
    ForwardAgent no
    ClearAllForwardings yes
    RequestTTY no
EOF
awk '{ print "[host.docker.internal]:2222 " $1 " " $2 }' \
  "$transport_dir/ssh_host_ed25519_key.pub" > "$transport_dir/known_hosts"
# Public client files are recreated whenever /run is recreated at boot.
cat > "$transport_dir/prepare-runtime" <<'EOF'
#!/bin/sh
set -eu
for file in config known_hosts id_ed25519.pub; do
  install -o 1000 -g 1000 -m 0644 "/etc/wiki-lab-ssh/$file" "/run/wiki-lab-agent/$file"
done
EOF
chmod 0755 "$transport_dir/prepare-runtime"
cat > "$transport_dir/load-key" <<'EOF'
#!/bin/sh
set -eu
attempt=0
while [ ! -S /run/wiki-lab-agent/agent.sock ]; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 50 ] || { echo 'SSH agent socket did not appear' >&2; exit 1; }
  sleep 0.1
done
export SSH_AUTH_SOCK=/run/wiki-lab-agent/agent.sock
exec /usr/bin/ssh-add /etc/wiki-lab-ssh/id_ed25519
EOF
chmod 0755 "$transport_dir/load-key"
cat > /etc/systemd/system/wiki-lab-agent.service <<EOF
[Unit]
Description=Host-only SSH signing agent for Lab wiki Git
After=local-fs.target

[Service]
Type=simple
User=$git_user
Group=$(id -gn "$git_user")
RuntimeDirectory=wiki-lab-agent
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
Environment=SSH_AUTH_SOCK=$runtime_dir/agent.sock
ExecStartPre=+$transport_dir/prepare-runtime
ExecStartPre=/usr/bin/rm -f $runtime_dir/agent.sock
ExecStart=/usr/bin/ssh-agent -D -a $runtime_dir/agent.sock
ExecStartPost=+$transport_dir/load-key
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$runtime_dir
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/wiki-lab-sshd.service <<EOF
[Unit]
Description=Restricted wiki Git SSH endpoint on Docker bridge
Requires=docker.service
After=docker.service network.target

[Service]
Type=simple
ExecStartPre=/usr/bin/install -d -o root -g root -m 0755 /run/sshd
ExecStartPre=/usr/sbin/sshd -t -f $transport_dir/sshd_config
ExecStart=/usr/sbin/sshd -D -e -f $transport_dir/sshd_config
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
/usr/sbin/sshd -t -f "$transport_dir/sshd_config"
systemd-analyze verify /etc/systemd/system/wiki-lab-agent.service /etc/systemd/system/wiki-lab-sshd.service
systemctl daemon-reload
systemctl enable wiki-lab-agent.service wiki-lab-sshd.service
systemctl restart wiki-lab-agent.service wiki-lab-sshd.service
printf 'Wiki transport ready on %s:%s. Mount %s read-only into Lab only.\n' "$bridge_ip" "$port" "$runtime_dir"
