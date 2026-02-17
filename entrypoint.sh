#!/usr/bin/env bash
set -euo pipefail

OC="/home/node/.openclaw"
WS="$OC/workspace"
CFG="/opt/clawos/config"
TPL="/opt/clawos/defaults"

stamp() { printf "[clawos %s] " "$(date -u +%H:%M:%S)"; }

# ── 1. Provisioner mounts ───────────────────────────────────────────────────
# Swarm injects Docker configs; BYO uses bind mounts — same paths either way.

if [[ -f /run/configs/openclaw.json ]]; then
  stamp; echo "applying provisioner config"
  cp /run/configs/openclaw.json "$OC/openclaw.json"
elif [[ -f "$CFG/openclaw.json" ]]; then
  stamp; echo "applying default config"
  cp "$CFG/openclaw.json" "$OC/openclaw.json"
fi

if [[ -d /run/configs/workspace ]]; then
  stamp; echo "applying provisioner workspace files"
  cp -r /run/configs/workspace/. "$WS/"
fi

if [[ -f /run/configs/env ]]; then
  stamp; echo "sourcing provisioner env"
  set -a; source /run/configs/env; set +a
fi

# ── 2. Workspace templates (first-boot only) ────────────────────────────────
# -n flag prevents clobbering files that already exist from a previous boot
# or from provisioner mounts above.

for src in "$TPL"/workspace/*; do
  [[ -e "$src" ]] || continue
  dest="$WS/$(basename "$src")"
  if [[ ! -e "$dest" ]]; then
    stamp; echo "seeding $(basename "$src")"
    cp -r "$src" "$dest"
  fi
done

# ── 3. Platform security boundaries ─────────────────────────────────────────
# Written every boot — not user-editable.

if [[ -f "$CFG/security-rules.md" ]]; then
  stamp; echo "writing SECURITY.md"
  cp "$CFG/security-rules.md" "$WS/SECURITY.md"
fi

# ── 4. Managed skill installation ───────────────────────────────────────────
# Installs into ~/.openclaw/skills/ (middle tier).
# Users can override by placing a skill in workspace/skills/ (top tier).

install_skills() {
  local manifest="$1"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    # drop anything after #, collapse spaces
    local name
    name="$(printf '%s' "${raw}" | sed 's/#.*//;s/[[:space:]]//g')"
    [[ -z "$name" ]] && continue

    if [[ -d "$OC/skills/$name" ]]; then
      stamp; echo "  $name — present"
    else
      stamp; echo "  $name — installing"
      (cd "$OC" && clawhub install "$name" 2>&1 | sed 's/^/    /') \
        || { stamp; echo "  $name — failed (non-fatal)"; }
    fi
  done < "$manifest"
}

if [[ -f "$CFG/skills-manifest.txt" ]]; then
  stamp; echo "checking managed skills"
  install_skills "$CFG/skills-manifest.txt"
fi

# ── Hand off ────────────────────────────────────────────────────────────────

stamp; echo "starting gateway"
exec "$@"
