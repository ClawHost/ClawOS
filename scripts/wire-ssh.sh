#!/usr/bin/env bash
# Wire SSH access into the container.
# Starts sshd on port 2222 if CLAWOS_SSH_AUTHORIZED_KEY is set.
# Requires: lib.sh (log).

wire_ssh() {
  [[ -z "${CLAWOS_SSH_AUTHORIZED_KEY:-}" ]] && return 0

  log "ssh: configuring sshd on port 2222"

  # sshd config: key-only, no password, no root login
  cat > /etc/ssh/sshd_config.d/clawos.conf <<'EOF'
Port 2222
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /home/node/.ssh/authorized_keys
PermitRootLogin no
AllowUsers node
X11Forwarding no
PrintMotd no
EOF

  # Write authorized_keys for node user
  mkdir -p /home/node/.ssh
  echo "${CLAWOS_SSH_AUTHORIZED_KEY}" > /home/node/.ssh/authorized_keys
  chmod 700 /home/node/.ssh
  chmod 600 /home/node/.ssh/authorized_keys
  chown -R node:node /home/node/.ssh

  # Start sshd in background (runs as root, drops privs per connection)
  /usr/sbin/sshd -f /etc/ssh/sshd_config
  log "ssh: sshd started on port 2222"
}
