#!/usr/bin/env bash
set -euo pipefail

# ── Constants ───────────────────────────────────────────────────────────────
OC="/home/node/.openclaw"
WS="$OC/workspace"
CFG="/opt/clawos/config"
TPL="/opt/clawos/defaults"
RUN_CFG="/run/configs"
WHISPER_BIN="${WHISPER_CPP_PATH:-/usr/local/bin/whisper-cpp}"
WHISPER_DIR="${WHISPER_MODELS_DIR:-/opt/clawos/models/whisper}"
QMD_CACHE="${XDG_CACHE_HOME:-/home/node/.cache}/qmd"

log() { printf "[clawos %s] %s\n" "$(date -u +%H:%M:%S)" "$*"; }

# ── 0. Ensure directories exist (volumes may mount as empty) ──────────────
# Runs as root; final chown happens right before launch (after all writes).
if [[ "$(id -u)" = "0" ]]; then
  mkdir -p "$OC/workspace" "$QMD_CACHE" /home/node/.cache/ms-playwright
fi

# ── 1. Runtime environment (first — so env vars are available below) ────────
if [[ -f "$RUN_CFG/env" ]]; then
  log "sourcing runtime env"
  set -a; source "$RUN_CFG/env"; set +a
fi

# ── 2. Gateway config ──────────────────────────────────────────────────────
# Precedence: /run/configs/openclaw.json > baked default
if [[ -f "$RUN_CFG/openclaw.json" ]]; then
  log "applying runtime gateway config"
  cp "$RUN_CFG/openclaw.json" "$OC/openclaw.json"
elif [[ ! -f "$OC/openclaw.json" ]]; then
  log "applying default gateway config"
  cp "$CFG/openclaw.json" "$OC/openclaw.json"
fi

# ── 3. Env-based config patching (jq) ──────────────────────────────────────
# Patch individual fields without needing a full config override.
# All paths conform to the OpenClawConfig type schema.
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

  # gateway.controlUi — origin allowlist for WebSocket connections
  # Comma-separated origins, e.g. "http://localhost:3001,https://app.clawhost.com"
  # Use "*" to allow all origins (default for baked config).
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

  # tools.media.audio (whisper-cpp transcription)
  if [[ "${CLAWOS_WHISPER_ENABLED:-}" == "false" ]]; then
    filter="$filter | .tools.media.audio.enabled = false | .skills.entries.whisper.enabled = false"
  elif [[ "${CLAWOS_WHISPER_ENABLED:-}" == "true" ]]; then
    filter="$filter | .tools.media.audio.enabled = true | .skills.entries.whisper.enabled = true"
  fi

  # skills.entries.whisper.config
  [[ -n "${CLAWOS_WHISPER_MODEL:-}" ]] \
    && filter="$filter | .skills.entries.whisper.config.model = env.CLAWOS_WHISPER_MODEL"

  [[ -n "${CLAWOS_WHISPER_THREADS:-}" ]] \
    && filter="$filter | .skills.entries.whisper.config.threads = (env.CLAWOS_WHISPER_THREADS | tonumber)"

  # skills.entries.qmd
  if [[ "${CLAWOS_QMD_ENABLED:-}" == "false" ]]; then
    filter="$filter | .skills.entries.qmd.enabled = false"
  elif [[ "${CLAWOS_QMD_ENABLED:-}" == "true" ]]; then
    filter="$filter | .skills.entries.qmd.enabled = true"
  fi

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

[[ -f "$OC/openclaw.json" ]] && patch_config

# ── 3b. Auth — wire API keys into OpenClaw auth profiles ─────────────────
# OpenClaw uses auth profiles + env.vars to resolve credentials.
#
# MODEL PROVIDER KEYS (set one — creates auth profile + env.vars entry):
#   OPENROUTER_API_KEY    — routes all models through OpenRouter (recommended)
#   ANTHROPIC_API_KEY     — direct Anthropic (Claude)
#   OPENAI_API_KEY        — direct OpenAI (GPT, o1, o3)
#   GOOGLE_API_KEY        — direct Google (Gemini)
#   GROQ_API_KEY          — direct Groq (fast inference)
#   MISTRAL_API_KEY       — direct Mistral
#   DEEPSEEK_API_KEY      — direct DeepSeek
#   XAI_API_KEY           — direct xAI (Grok)
#   COHERE_API_KEY        — direct Cohere (Command R)
#   TOGETHER_API_KEY      — direct Together AI
#   FIREWORKS_API_KEY     — direct Fireworks AI
#   CEREBRAS_API_KEY      — direct Cerebras
#   AI21_API_KEY          — direct AI21 (Jamba)
#   GITHUB_COPILOT_TOKEN  — GitHub Copilot (token auth)
#
# TOOL KEYS (pass-through — OpenClaw reads these from env automatically):
#   PERPLEXITY_API_KEY    — Perplexity search (tools.webSearch)
#   BRAVE_API_KEY         — Brave Search (tools.webSearch)
#   FIRECRAWL_API_KEY     — Firecrawl web scraper (tools.webSearch fallback)
#   ELEVENLABS_API_KEY    — ElevenLabs TTS (talk/tts)
#
# OpenRouter mode (OPENROUTER_API_KEY set):
#   - Adds "openrouter:manual" auth profile
#   - Registers models.providers.openrouter with baseUrl
#   - Prefixes model ID with "openrouter/" so OpenClaw routes correctly
#
# Direct mode (provider-specific key):
#   - Adds "<provider>:manual" auth profile
#   - Model ID used as-is (e.g. "anthropic/claude-sonnet-4-5")
wire_auth() {
  local file="$OC/openclaw.json"
  local filter="."
  local provider_count=0

  # OpenRouter mode — single key routes to all providers
  if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    log "auth: configuring OpenRouter"
    filter="$filter
      | .env.vars.OPENROUTER_API_KEY = \"\${OPENROUTER_API_KEY}\"
      | .auth.profiles[\"openrouter:manual\"] = {\"provider\": \"openrouter\", \"mode\": \"api_key\"}
      | .auth.order.openrouter = [\"openrouter:manual\"]
      | .models.providers.openrouter = {
          \"baseUrl\": \"https://openrouter.ai/api/v1\",
          \"api\": \"openai-responses\",
          \"models\": [{
            \"id\": (.agents.defaults.model.primary // \"anthropic/claude-sonnet-4-5\"),
            \"name\": (.agents.defaults.model.primary // \"anthropic/claude-sonnet-4-5\"),
            \"reasoning\": false,
            \"input\": [\"text\", \"image\"],
            \"cost\": {\"input\": 0, \"output\": 0, \"cacheRead\": 0, \"cacheWrite\": 0},
            \"contextWindow\": (.agents.defaults.contextTokens // 200000),
            \"maxTokens\": 8192
          }]
        }
      | .agents.defaults.model.primary = (\"openrouter/\" + (.agents.defaults.model.primary // \"anthropic/claude-sonnet-4-5\"))"
    provider_count=$((provider_count + 1))
  fi

  # ── Direct model provider keys ─────────────────────────────────────────
  # Each entry: ENV_VAR_NAME=openclaw_provider_name
  # Auth mode is "api_key" for all except GitHub Copilot (token).
  declare -A providers=(
    [ANTHROPIC_API_KEY]=anthropic
    [OPENAI_API_KEY]=openai
    [GOOGLE_API_KEY]=google
    [GROQ_API_KEY]=groq
    [MISTRAL_API_KEY]=mistral
    [DEEPSEEK_API_KEY]=deepseek
    [XAI_API_KEY]=xai
    [COHERE_API_KEY]=cohere
    [TOGETHER_API_KEY]=together
    [FIREWORKS_API_KEY]=fireworks
    [CEREBRAS_API_KEY]=cerebras
    [AI21_API_KEY]=ai21
  )

  for env_var in "${!providers[@]}"; do
    local provider="${providers[$env_var]}"
    local val="${!env_var:-}"
    if [[ -n "$val" ]]; then
      log "auth: configuring $provider (direct key)"
      filter="$filter
        | .env.vars.${env_var} = \"\${${env_var}}\"
        | .auth.profiles[\"${provider}:manual\"] = {\"provider\": \"${provider}\", \"mode\": \"api_key\"}
        | .auth.order.${provider} = [\"${provider}:manual\"]"
      provider_count=$((provider_count + 1))
    fi
  done

  # GitHub Copilot uses "token" auth mode, not "api_key"
  if [[ -n "${GITHUB_COPILOT_TOKEN:-}" ]]; then
    log "auth: configuring github-copilot (token)"
    filter="$filter
      | .env.vars.GITHUB_COPILOT_TOKEN = \"\${GITHUB_COPILOT_TOKEN}\"
      | .auth.profiles[\"github-copilot:manual\"] = {\"provider\": \"github-copilot\", \"mode\": \"token\"}
      | .auth.order[\"github-copilot\"] = [\"github-copilot:manual\"]"
    provider_count=$((provider_count + 1))
  fi

  # ── Tool / service keys (pass-through only, no auth profiles) ──────────
  # OpenClaw reads these from the process env automatically.
  # We inject them into env.vars so ${ENV} substitution works in configs.
  declare -A tool_keys=(
    [PERPLEXITY_API_KEY]="Perplexity search"
    [BRAVE_API_KEY]="Brave Search"
    [FIRECRAWL_API_KEY]="Firecrawl scraper"
    [ELEVENLABS_API_KEY]="ElevenLabs TTS"
  )

  local tool_count=0
  for env_var in "${!tool_keys[@]}"; do
    local val="${!env_var:-}"
    if [[ -n "$val" ]]; then
      local label="${tool_keys[$env_var]}"
      log "auth: passing $label key"
      filter="$filter | .env.vars.${env_var} = \"\${${env_var}}\""
      tool_count=$((tool_count + 1))
    fi
  done

  if [[ "$provider_count" -eq 0 ]]; then
    log "warning: no model API keys provided — set OPENROUTER_API_KEY or a provider-specific key"
    return 0
  fi

  log "auth: wiring $provider_count model provider(s), $tool_count tool key(s)"
  local tmp
  tmp=$(mktemp)
  if jq "$filter" "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
  else
    log "warning: auth profile patching failed"
    rm -f "$tmp"
  fi
}

[[ -f "$OC/openclaw.json" ]] && wire_auth

# ── 4. Workspace files ─────────────────────────────────────────────────────
# Runtime workspace overrides (soul, identity, agents, etc.)
if [[ -d "$RUN_CFG/workspace" ]]; then
  log "applying runtime workspace files"
  cp -r "$RUN_CFG/workspace/." "$WS/"
fi

# First-boot template seeding (skip files that already exist)
for src in "$TPL"/workspace/*; do
  [[ -e "$src" ]] || continue
  base="$(basename "$src")"
  [[ -e "$WS/$base" ]] || { log "seeding $base"; cp -r "$src" "$WS/$base"; }
done

# ── 5. Security boundaries (always overwritten) ────────────────────────────
[[ -f "$CFG/security-rules.md" ]] && cp "$CFG/security-rules.md" "$WS/SECURITY.md"

# ── 6. Extra skills (runtime additions beyond pre-baked base) ──────────────
# Set CLAWOS_EXTRA_SKILLS="skill-a,skill-b" to install additional skills.
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
      (cd "$OC" && clawhub install "$name" 2>&1 | sed 's/^/    /') \
        || log "  $name — failed (non-fatal)"
    fi
  done
fi

# ── 7. Optional skill verification (off by default for speed) ──────────────
# Set CLAWOS_VERIFY_SKILLS=true to check pre-baked skills are intact.
if [[ "${CLAWOS_VERIFY_SKILLS:-false}" == "true" && -f "$CFG/skills-manifest.txt" ]]; then
  log "verifying managed skills"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    name="$(printf '%s' "$raw" | sed 's/#.*//;s/[[:space:]]//g')"
    [[ -z "$name" ]] && continue
    if [[ -d "$OC/skills/$name" ]]; then
      log "  $name — ok"
    else
      log "  $name — missing, reinstalling"
      (cd "$OC" && clawhub install "$name" 2>&1 | sed 's/^/    /') \
        || log "  $name — failed (non-fatal)"
    fi
  done < "$CFG/skills-manifest.txt"
fi

# ── 8. whisper-cpp status ───────────────────────────────────────────────────
if [[ -x "$WHISPER_BIN" ]]; then
  default_model=""
  [[ -f "$WHISPER_DIR/.default-model" ]] && default_model=$(cat "$WHISPER_DIR/.default-model")
  active_model="${CLAWOS_WHISPER_MODEL:-$default_model}"
  model_file="$WHISPER_DIR/ggml-${active_model}.bin"

  if [[ "${CLAWOS_WHISPER_ENABLED:-true}" == "true" ]]; then
    if [[ -f "$model_file" ]]; then
      model_size=$(du -sh "$model_file" | cut -f1)
      log "whisper-cpp ready — model=$active_model ($model_size), bin=$WHISPER_BIN"
    else
      log "whisper-cpp binary present but model not found: $model_file"
      log "  available models:"
      for m in "$WHISPER_DIR"/ggml-*.bin; do
        [[ -f "$m" ]] && log "    $(basename "$m")"
      done
    fi
  else
    log "whisper-cpp disabled (CLAWOS_WHISPER_ENABLED=false)"
  fi
else
  log "whisper-cpp not available (binary not found at $WHISPER_BIN)"
fi

# ── 9. QMD local search ────────────────────────────────────────────────────
# Index the workspace on first boot so `qmd search` works immediately.
# BM25 keyword search works without GGUF models (instant).
# Semantic search (vsearch/query) downloads models on first use (~2 GB).
if [[ "${CLAWOS_QMD_ENABLED:-true}" == "true" ]] && command -v qmd &>/dev/null; then
  log "qmd ready — $(qmd --version 2>/dev/null || echo 'version unknown')"

  # Auto-index workspace on first boot (BM25 only — fast, no model download)
  if [[ ! -f "$QMD_CACHE/index.sqlite" ]]; then
    log "qmd first boot — indexing workspace"
    qmd collection add "$WS" --name workspace --mask "**/*.md" 2>&1 | sed 's/^/    /' \
      || log "  qmd collection add failed (non-fatal)"
    qmd context add qmd://workspace "Agent workspace: memory, notes, canvas, skills" 2>&1 | sed 's/^/    /' \
      || true
    qmd update 2>&1 | sed 's/^/    /' \
      || log "  qmd update failed (non-fatal)"
  fi

  # If provisioner mounted extra QMD collections, apply them
  if [[ -f "$RUN_CFG/qmd-collections.sh" ]]; then
    log "applying provisioner QMD collections"
    bash "$RUN_CFG/qmd-collections.sh" 2>&1 | sed 's/^/    /' \
      || log "  qmd-collections.sh failed (non-fatal)"
  fi
else
  if [[ "${CLAWOS_QMD_ENABLED:-true}" == "false" ]]; then
    log "qmd disabled (CLAWOS_QMD_ENABLED=false)"
  else
    log "qmd not available (binary not found)"
  fi
fi

# ── Launch ──────────────────────────────────────────────────────────────────
# Final ownership fix: all config writes above ran as root. Hand everything
# to node before dropping privileges.
if [[ "$(id -u)" = "0" ]]; then
  chown -R node:node "$OC" /home/node/.cache
fi

log "starting gateway (port ${CLAWOS_PORT:-18789})"
if [[ "$(id -u)" = "0" ]]; then
  exec gosu node "$@"
else
  exec "$@"
fi
