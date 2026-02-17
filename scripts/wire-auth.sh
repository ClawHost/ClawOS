#!/usr/bin/env bash
# Wire API keys into OpenClaw auth profiles and env.vars.
# Requires: lib.sh (OC, log). See README or entrypoint for env var list.

wire_auth() {
  local file="$OC/openclaw.json"
  local filter="."
  local provider_count=0

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

  if [[ -n "${GITHUB_COPILOT_TOKEN:-}" ]]; then
    log "auth: configuring github-copilot (token)"
    filter="$filter
      | .env.vars.GITHUB_COPILOT_TOKEN = \"\${GITHUB_COPILOT_TOKEN}\"
      | .auth.profiles[\"github-copilot:manual\"] = {\"provider\": \"github-copilot\", \"mode\": \"token\"}
      | .auth.order[\"github-copilot\"] = [\"github-copilot:manual\"]"
    provider_count=$((provider_count + 1))
  fi

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
