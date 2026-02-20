# syntax=docker/dockerfile:1
###############################################################################
# ClawOS — Clawhost Agent Runtime
#
# Structure:
#   Stage 1 (whisper-builder)  docker/whisper-build.sh
#   Stage 2 (base)             system pkgs → npm → layout → skills → whisper → config → scripts → entrypoint → ENV
#   See docker/env.vars for runtime ENV list.
###############################################################################

# ━━━ Stage 1: whisper.cpp builder ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM debian:bookworm-slim AS whisper-builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates curl

ARG WHISPER_CPP_VERSION=v1.8.3
ARG WHISPER_MODEL=base
COPY docker/whisper-build.sh /tmp/whisper-build.sh
RUN chmod +x /tmp/whisper-build.sh && /tmp/whisper-build.sh

# ━━━ Stage 2: runtime ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM node:22-bookworm-slim AS base

# System packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates chromium curl ffmpeg git gnupg gosu jq libgomp1 sqlite3 tini \
 && rm -rf /var/lib/apt/lists/*

ENV CHROMIUM_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright

# OpenClaw + Clawhub + QMD
ARG OC_VERSION=2026.2.15
RUN --mount=type=cache,target=/root/.npm \
    npm install -g "openclaw@${OC_VERSION}" clawhub @tobilu/qmd

# Filesystem layout
RUN mkdir -p \
      /home/node/.openclaw/workspace/{memory,skills,canvas} \
      /home/node/.openclaw/{skills,agents/main/sessions,credentials,sandboxes,canvas,cron} \
      /home/node/.cache/{ms-playwright,qmd/models} \
      /.clawhub /opt/clawos/{config,defaults/workspace,models/whisper,scripts} \
      /run/configs \
 && chown -R node:node /home/node/.openclaw /home/node/.cache /.clawhub /opt/clawos /run/configs

# Pre-bake skills
COPY config/skills-manifest.txt /opt/clawos/config/skills-manifest.txt
RUN --mount=type=cache,target=/home/node/.npm,uid=1000,gid=1000 \
    chown node:node /opt/clawos/config/skills-manifest.txt \
 && su node -c 'set -e; cd /home/node/.openclaw; \
    while IFS= read -r line || [ -n "$line" ]; do \
      name="$(printf "%s" "$line" | sed "s/#.*//;s/[[:space:]]//g")"; \
      [ -z "$name" ] && continue; \
      echo "[build] pre-installing skill: $name"; \
      clawhub install --force "$name" 2>&1 || echo "[build] warning: $name install failed (non-fatal)"; \
    done < /opt/clawos/config/skills-manifest.txt'

# Bundled skills (not in clawhub registry)
COPY skills/ /home/node/.openclaw/skills/
RUN chown -R node:node /home/node/.openclaw/skills/

# Skillbase CLI
COPY bin/skillbase /usr/local/bin/skillbase
RUN chmod +x /usr/local/bin/skillbase

# Whisper binary, libs, model + symlinks
COPY --from=whisper-builder /usr/local/bin/whisper-cli /usr/local/bin/whisper-cli
COPY --from=whisper-builder /usr/local/lib/whisper/ /usr/local/lib/
COPY --from=whisper-builder /opt/whisper-models/ /opt/clawos/models/whisper/
COPY docker/whisper-symlinks.sh /tmp/whisper-symlinks.sh
RUN chmod +x /tmp/whisper-symlinks.sh && /tmp/whisper-symlinks.sh

# Config, defaults, entrypoint scripts
COPY config/    /opt/clawos/config/
COPY defaults/  /opt/clawos/defaults/
COPY scripts/   /opt/clawos/scripts/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && chown -R node:node /opt/clawos

# Runtime ENV (see docker/env.vars for list)
ENV OPENROUTER_API_KEY="" \
    ANTHROPIC_API_KEY="" \
    OPENAI_API_KEY="" \
    GOOGLE_API_KEY="" \
    GROQ_API_KEY="" \
    MISTRAL_API_KEY="" \
    DEEPSEEK_API_KEY="" \
    XAI_API_KEY="" \
    COHERE_API_KEY="" \
    TOGETHER_API_KEY="" \
    FIREWORKS_API_KEY="" \
    CEREBRAS_API_KEY="" \
    AI21_API_KEY="" \
    GITHUB_COPILOT_TOKEN="" \
    PERPLEXITY_API_KEY="" \
    BRAVE_API_KEY="" \
    FIRECRAWL_API_KEY="" \
    ELEVENLABS_API_KEY="" \
    CLAWOS_PORT="" \
    CLAWOS_ALLOWED_ORIGINS="" \
    CLAWOS_TLS_ENABLED="" \
    CLAWOS_MODEL="" \
    CLAWOS_CONTEXT_TOKENS="" \
    CLAWOS_MAX_CONCURRENT="" \
    CLAWOS_TIMEOUT="" \
    CLAWOS_LOG_LEVEL="" \
    CLAWOS_TOOLS_PROFILE="" \
    CLAWOS_SANDBOX_MEMORY="" \
    CLAWOS_COMPACTION_MODE="" \
    CLAWOS_EXTRA_SKILLS="" \
    CLAWOS_VERIFY_SKILLS=false \
    CLAWOS_WHATSAPP_ENABLED="" \
    CLAWOS_TELEGRAM_ALLOW_FROM="" \
    CLAWOS_WHISPER_MODEL="" \
    CLAWOS_WHISPER_THREADS="" \
    WHISPER_CPP_PATH=/usr/local/bin/whisper-cli \
    WHISPER_MODELS_DIR=/opt/clawos/models/whisper \
    CLAWOS_QMD_ENABLED=true \
    CLAWOS_TTS_AUTO="" \
    CLAWOS_TTS_PROVIDER="" \
    CLAWOS_TTS_VOICE="" \
    XDG_CACHE_HOME=/home/node/.cache

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -sf http://127.0.0.1:${CLAWOS_PORT:-18789}/ || exit 1

# No USER directive: entrypoint runs as root, fixes volume ownership, then gosu node.
WORKDIR /home/node
EXPOSE 18789 18793
LABEL org.opencontainers.image.title="ClawOS" \
      org.opencontainers.image.description="Clawhost Agent Runtime" \
      org.opencontainers.image.vendor="Clawhost" \
      org.opencontainers.image.source="https://github.com/clawhost/clawos"

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
