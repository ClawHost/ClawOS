#!/usr/bin/env bash
# Env-based config patching (jq). All paths conform to OpenClawConfig schema.
# Requires: lib.sh (OC, log). Uses: openclaw.json at $OC/openclaw.json

patch_config() {
  local file="$OC/openclaw.json"
  local filter="."

  # agents.defaults
  [[ -n "${CLAWOS_MODEL:-}" ]] \
    && filter="$filter | .agents.defaults.model.primary = env.CLAWOS_MODEL"
  [[ -n "${CLAWOS_CONTEXT_TOKENS:-}" ]] \
    && filter="$filter | .agents.defaults.contextTokens = (env.CLAWOS_CONTEXT_TOKENS | tonumber)"
  [[ -n "${CLAWOS_MAX_CONCURRENT:-}" ]] \
    && filter="$filter | .agents.defaults.maxConcurrent = (env.CLAWOS_MAX_CONCURRENT | tonumber)"
  [[ -n "${CLAWOS_TIMEOUT:-}" ]] \
    && filter="$filter | .agents.defaults.timeoutSeconds = (env.CLAWOS_TIMEOUT | tonumber)"
  [[ -n "${CLAWOS_SANDBOX_MEMORY:-}" ]] \
    && filter="$filter | .agents.defaults.sandbox.docker.memory = env.CLAWOS_SANDBOX_MEMORY"
  [[ -n "${CLAWOS_COMPACTION_MODE:-}" ]] \
    && filter="$filter | .agents.defaults.compaction.mode = env.CLAWOS_COMPACTION_MODE"

  # gateway
  [[ -n "${CLAWOS_PORT:-}" ]] \
    && filter="$filter | .gateway.port = (env.CLAWOS_PORT | tonumber)"
  if [[ -n "${CLAWOS_ALLOWED_ORIGINS:-}" ]]; then
    filter="$filter | .gateway.controlUi.allowedOrigins = (env.CLAWOS_ALLOWED_ORIGINS | split(\",\") | map(gsub(\"^\\\\s+|\\\\s+$\"; \"\")))"
  fi
  if [[ "${CLAWOS_TLS_ENABLED:-}" == "true" ]]; then
    filter="$filter | .gateway.tls.enabled = true | .gateway.controlUi.allowInsecureAuth = false"
  elif [[ "${CLAWOS_TLS_ENABLED:-}" == "false" ]]; then
    filter="$filter | .gateway.tls.enabled = false | .gateway.controlUi.allowInsecureAuth = true"
  fi

  # logging
  [[ -n "${CLAWOS_LOG_LEVEL:-}" ]] \
    && filter="$filter | .logging.level = env.CLAWOS_LOG_LEVEL | .logging.consoleLevel = env.CLAWOS_LOG_LEVEL"

  # tools
  [[ -n "${CLAWOS_TOOLS_PROFILE:-}" ]] \
    && filter="$filter | .tools.profile = env.CLAWOS_TOOLS_PROFILE"

  # tools.media.audio (whisper-cli)
  if [[ -n "${CLAWOS_WHISPER_MODEL:-}" ]]; then
    local model_path="/opt/clawos/models/whisper/ggml-${CLAWOS_WHISPER_MODEL}.bin"
    filter="$filter | .tools.media.audio.models[0].args[1] = \"$model_path\""
  fi
  if [[ -n "${CLAWOS_WHISPER_THREADS:-}" ]]; then
    filter="$filter | .tools.media.audio.models[0].args[5] = env.CLAWOS_WHISPER_THREADS"
  fi

  # skills.entries.qmd
  if [[ "${CLAWOS_QMD_ENABLED:-}" == "false" ]]; then
    filter="$filter | .skills.entries.qmd.enabled = false"
  elif [[ "${CLAWOS_QMD_ENABLED:-}" == "true" ]]; then
    filter="$filter | .skills.entries.qmd.enabled = true"
  fi

  # messages.tts
  [[ -n "${CLAWOS_TTS_AUTO:-}" ]] \
    && filter="$filter | .messages.tts.auto = env.CLAWOS_TTS_AUTO"
  [[ -n "${CLAWOS_TTS_PROVIDER:-}" ]] \
    && filter="$filter | .messages.tts.provider = env.CLAWOS_TTS_PROVIDER"
  [[ -n "${CLAWOS_TTS_VOICE:-}" ]] \
    && filter="$filter | .messages.tts.edge.voice = env.CLAWOS_TTS_VOICE"

  if [[ "$filter" != "." ]]; then
    log "patching config from environment"
    local tmp
    tmp=$(mktemp)
    if jq "$filter" "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file"
    else
      log "warning: config patch failed, keeping original"
      rm -f "$tmp"
    fi
  fi
}
