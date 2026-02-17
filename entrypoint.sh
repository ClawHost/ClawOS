#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="/home/node/.openclaw"

###############################################################################
# Copy Docker config mounts into OpenClaw directory
# Swarm configs are mounted at /run/configs/; BYO mounts use the same paths.
###############################################################################

# openclaw.json — main agent config
if [[ -f /run/configs/openclaw.json ]]; then
  echo "[entrypoint] Copying openclaw.json from config mount"
  cp /run/configs/openclaw.json "$OPENCLAW_HOME/openclaw.json"
fi

# Workspace files (SOUL.md, IDENTITY.md, USER.md, AGENTS.md, etc.)
if [[ -d /run/configs/workspace ]]; then
  echo "[entrypoint] Copying workspace files from config mount"
  cp -r /run/configs/workspace/. "$OPENCLAW_HOME/workspace/"
fi

# Env file (secrets injected by provisioner)
if [[ -f /run/configs/env ]]; then
  echo "[entrypoint] Loading environment from config mount"
  set -a
  source /run/configs/env
  set +a
fi

###############################################################################
# Hand off to the real command (CMD)
###############################################################################
exec "$@"
