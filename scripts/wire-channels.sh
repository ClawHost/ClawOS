#!/usr/bin/env bash
# Wire IM/messaging tokens into OpenClaw channels + plugins.
# Merges into existing channel config (preserves allowFrom, dmPolicy, etc.).
# Requires: lib.sh (OC, log). Env: TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, etc.

wire_channels() {
  local file="$OC/openclaw.json"
  local filter="."
  local channel_count=0

  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    log "channels: enabling Telegram"
    # Merge token + defaults without clobbering existing keys (allowFrom, dmPolicy, etc.)
    filter="$filter
      | .env.vars.TELEGRAM_BOT_TOKEN = \"\${TELEGRAM_BOT_TOKEN}\"
      | .channels.telegram.enabled = true
      | .channels.telegram.botToken = \"\${TELEGRAM_BOT_TOKEN}\"
      | .channels.telegram.dmPolicy //= \"pairing\"
      | .channels.telegram.groupPolicy //= \"allowlist\"
      | .channels.telegram.streamMode //= \"partial\"
      | .plugins.entries.telegram = {\"enabled\": true}"
    # Allow env-based override for allowlist (standalone/docker-compose usage)
    if [[ -n "${CLAWOS_TELEGRAM_ALLOW_FROM:-}" ]]; then
      filter="$filter
        | .channels.telegram.dmPolicy = \"allowlist\"
        | .channels.telegram.allowFrom = (env.CLAWOS_TELEGRAM_ALLOW_FROM | split(\",\") | map(gsub(\"^\\\\s+|\\\\s+$\"; \"\") | select(length > 0) | tonumber))"
      log "channels: Telegram allowlist (env override): ${CLAWOS_TELEGRAM_ALLOW_FROM}"
    fi
    channel_count=$((channel_count + 1))
  fi

  if [[ -n "${DISCORD_BOT_TOKEN:-}" ]]; then
    log "channels: enabling Discord"
    filter="$filter
      | .env.vars.DISCORD_BOT_TOKEN = \"\${DISCORD_BOT_TOKEN}\"
      | .channels.discord.enabled = true
      | .channels.discord.token = \"\${DISCORD_BOT_TOKEN}\"
      | .channels.discord.dm.policy //= \"pairing\"
      | .plugins.entries.discord = {\"enabled\": true}"
    channel_count=$((channel_count + 1))
  fi

  if [[ -n "${SLACK_BOT_TOKEN:-}" ]] || [[ -n "${SLACK_APP_TOKEN:-}" ]]; then
    log "channels: enabling Slack"
    filter="$filter
      | .env.vars.SLACK_BOT_TOKEN = \"\${SLACK_BOT_TOKEN}\"
      | .env.vars.SLACK_APP_TOKEN = \"\${SLACK_APP_TOKEN}\"
      | .channels.slack.enabled = true
      | .channels.slack.botToken = \"\${SLACK_BOT_TOKEN}\"
      | .channels.slack.appToken = \"\${SLACK_APP_TOKEN}\"
      | .channels.slack.dm.policy //= \"pairing\"
      | .plugins.entries.slack = {\"enabled\": true}"
    channel_count=$((channel_count + 1))
  fi

  if [[ "${CLAWOS_WHATSAPP_ENABLED:-}" == "true" ]]; then
    log "channels: enabling WhatsApp (QR pairing at runtime)"
    filter="$filter
      | .channels.whatsapp.dmPolicy //= \"pairing\"
      | .channels.whatsapp.accounts.default.enabled = true
      | .plugins.entries.whatsapp = {\"enabled\": true}"
    channel_count=$((channel_count + 1))
  fi

  if [[ "$channel_count" -eq 0 ]]; then
    return 0
  fi

  log "channels: wired $channel_count channel(s)"
  local tmp
  tmp=$(mktemp)
  if jq "$filter" "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
  else
    log "warning: channel wiring failed"
    rm -f "$tmp"
  fi
}
