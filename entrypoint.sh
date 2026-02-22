#!/usr/bin/env bash
set -euo pipefail

# ClawOS entrypoint — minimal orchestrator. Logic lives in /opt/clawos/scripts/.
# Defaults (overridden by lib.sh when present).
OC="${OC:-/home/node/.openclaw}"
WS="${WS:-$OC/workspace}"
CFG="${CFG:-/opt/clawos/config}"
TPL="${TPL:-/opt/clawos/defaults}"
RUN_CFG="${RUN_CFG:-/run/configs}"
WHISPER_BIN="${WHISPER_CPP_PATH:-/usr/local/bin/whisper-cli}"
WHISPER_DIR="${WHISPER_MODELS_DIR:-/opt/clawos/models/whisper}"
QMD_CACHE="${XDG_CACHE_HOME:-/home/node/.cache}/qmd"
log() { printf "[clawos %s] %s\n" "$(date -u +%H:%M:%S)" "$*"; }

CLAWOS_SCRIPTS="${CLAWOS_SCRIPTS:-/opt/clawos/scripts}"
# shellcheck source=/dev/null
[[ -f "$CLAWOS_SCRIPTS/lib.sh" ]] && source "$CLAWOS_SCRIPTS/lib.sh"

# ── 0. Ensure directories exist (volumes may mount as empty) ─────────────────
if [[ "$(id -u)" = "0" ]]; then
  mkdir -p "$OC/workspace" "$QMD_CACHE" /home/node/.cache/ms-playwright
fi

# ── 1. Runtime environment ─────────────────────────────────────────────────
if [[ -f "$RUN_CFG/env" ]]; then
  log "sourcing runtime env"
  set -a; source "$RUN_CFG/env"; set +a
fi

# ── 2. Gateway config ──────────────────────────────────────────────────────
if [[ -f "$RUN_CFG/openclaw.json" ]]; then
  log "applying runtime gateway config"
  cp "$RUN_CFG/openclaw.json" "$OC/openclaw.json"
elif [[ ! -f "$OC/openclaw.json" ]]; then
  log "applying default gateway config"
  cp "$CFG/openclaw.json" "$OC/openclaw.json"
fi

# ── 3. Config patching + auth + channels (sourced from scripts) ──────────────
if [[ -f "$OC/openclaw.json" ]]; then
  [[ -f "$CLAWOS_SCRIPTS/patch-config.sh" ]] && source "$CLAWOS_SCRIPTS/patch-config.sh" && patch_config
  [[ -f "$CLAWOS_SCRIPTS/wire-auth.sh" ]]    && source "$CLAWOS_SCRIPTS/wire-auth.sh"    && wire_auth
  [[ -f "$CLAWOS_SCRIPTS/wire-channels.sh" ]] && source "$CLAWOS_SCRIPTS/wire-channels.sh" && wire_channels
  [[ -f "$CLAWOS_SCRIPTS/wire-ssh.sh" ]]      && source "$CLAWOS_SCRIPTS/wire-ssh.sh"      && wire_ssh
fi

# ── 4. Workspace files ─────────────────────────────────────────────────────
if [[ -d "$RUN_CFG/workspace" ]]; then
  log "applying runtime workspace files"
  # Skills live in $OC/skills/, not $WS/skills/ — copy them to the right place
  if [[ -d "$RUN_CFG/workspace/skills" ]]; then
    log "  copying user skills to $OC/skills/"
    cp -r "$RUN_CFG/workspace/skills/." "$OC/skills/"
  fi
  # Copy remaining workspace files (excluding skills/)
  for item in "$RUN_CFG/workspace"/*; do
    [[ -e "$item" ]] || continue
    base="$(basename "$item")"
    [[ "$base" == "skills" ]] && continue
    cp -r "$item" "$WS/$base"
  done
fi
for src in "$TPL"/workspace/*; do
  [[ -e "$src" ]] || continue
  base="$(basename "$src")"
  [[ -e "$WS/$base" ]] || { log "seeding $base"; cp -r "$src" "$WS/$base"; }
done

# ── 5. Security boundaries ─────────────────────────────────────────────────
[[ -f "$CFG/security-rules.md" ]] && cp "$CFG/security-rules.md" "$WS/SECURITY.md"

# ── 6. Extra skills ────────────────────────────────────────────────────────
if [[ -n "${CLAWOS_EXTRA_SKILLS:-}" ]]; then
  log "installing extra skills"
  IFS=',' read -ra extras <<< "$CLAWOS_EXTRA_SKILLS"
  for name in "${extras[@]}"; do
    name="${name// /}"
    [[ -z "$name" ]] && continue
    if [[ -d "$OC/skills/$name" ]]; then
      log "  $name — present"
    else
      log "  $name — installing"
      (cd "$OC" && clawhub install --force "$name" 2>&1 | sed 's/^/    /') \
        || log "  $name — failed (non-fatal)"
    fi
  done
fi

# ── 7. Skill verification ──────────────────────────────────────────────────
if [[ "${CLAWOS_VERIFY_SKILLS:-false}" == "true" && -f "$CFG/skills-manifest.txt" ]]; then
  log "verifying managed skills"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    name="$(printf '%s' "$raw" | sed 's/#.*//;s/[[:space:]]//g')"
    [[ -z "$name" ]] && continue
    if [[ -d "$OC/skills/$name" ]]; then
      log "  $name — ok"
    else
      log "  $name — missing, reinstalling"
      (cd "$OC" && clawhub install --force "$name" 2>&1 | sed 's/^/    /') \
        || log "  $name — failed (non-fatal)"
    fi
  done < "$CFG/skills-manifest.txt"
fi

# ── 8. Whisper status + model symlinks ─────────────────────────────────────
if [[ -x "$WHISPER_BIN" ]]; then
  default_model=""
  [[ -f "$WHISPER_DIR/.default-model" ]] && default_model=$(cat "$WHISPER_DIR/.default-model")
  active_model="${CLAWOS_WHISPER_MODEL:-$default_model}"
  model_file="$WHISPER_DIR/ggml-${active_model}.bin"

  if [[ -f "$model_file" ]]; then
    model_size=$(du -sh "$model_file" | cut -f1)
    log "whisper-cpp ready — model=$active_model ($model_size), bin=$WHISPER_BIN"
    ln -sf "$model_file" "$WS/base.en" 2>/dev/null || true
    ln -sf "$model_file" "$WS/base" 2>/dev/null || true
    ln -sf "$model_file" "$WS/ggml-base.bin" 2>/dev/null || true
    ln -sf "$model_file" "$WS/ggml-base.en.bin" 2>/dev/null || true
    ln -sf "$model_file" "/home/node/base.en" 2>/dev/null || true
    ln -sf "$model_file" "/home/node/base" 2>/dev/null || true
  else
    log "whisper-cpp binary present but model not found: $model_file"
    for m in "$WHISPER_DIR"/ggml-*.bin; do [[ -f "$m" ]] && log "    $(basename "$m")"; done
  fi
else
  log "whisper-cpp not available (binary not found at $WHISPER_BIN)"
fi

# ── 9. QMD local search ───────────────────────────────────────────────────
if [[ "${CLAWOS_QMD_ENABLED:-true}" == "true" ]] && command -v qmd &>/dev/null; then
  log "qmd ready — $(qmd --version 2>/dev/null || echo 'version unknown')"
  if [[ ! -f "$QMD_CACHE/index.sqlite" ]]; then
    log "qmd first boot — indexing workspace"
    qmd collection add "$WS" --name workspace --mask "**/*.md" 2>&1 | sed 's/^/    /' || log "  qmd collection add failed (non-fatal)"
    qmd context add qmd://workspace "Agent workspace: memory, notes, canvas, skills" 2>&1 | sed 's/^/    /' || true
    qmd update 2>&1 | sed 's/^/    /' || log "  qmd update failed (non-fatal)"
  fi
  if [[ -f "$RUN_CFG/qmd-collections.sh" ]]; then
    log "applying provisioner QMD collections"
    bash "$RUN_CFG/qmd-collections.sh" 2>&1 | sed 's/^/    /' || log "  qmd-collections.sh failed (non-fatal)"
  fi
else
  [[ "${CLAWOS_QMD_ENABLED:-true}" == "false" ]] && log "qmd disabled (CLAWOS_QMD_ENABLED=false)" || log "qmd not available (binary not found)"
fi

# ── Launch ──────────────────────────────────────────────────────────────────
if [[ "$(id -u)" = "0" ]]; then
  chown -R node:node "$OC" /home/node/.cache
fi

log "starting gateway (port ${CLAWOS_PORT:-18789})"
if [[ "$(id -u)" = "0" ]]; then
  exec gosu node "$@"
else
  exec "$@"
fi
