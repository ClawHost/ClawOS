# syntax=docker/dockerfile:1
###############################################################################
# ClawOS — Clawhost Agent Runtime
#
# Optimized for fast builds (BuildKit caches, layer ordering) and instant
# deploys (managed skills pre-baked, sub-second entrypoint).
#
# Multi-stage build:
#   1. whisper-builder — compiles whisper.cpp + downloads GGML model
#   2. base           — runtime image with everything ready to go
#
# BuildKit builds stages in parallel until the COPY join point.
#
# User-specific config is injected at runtime via:
#   /run/configs/   — Docker configs (Swarm) or bind mounts (BYO)
#   Environment     — CLAWOS_* vars patch gateway config on the fly
###############################################################################

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 1: whisper.cpp builder (runs in parallel with early runtime layers)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM debian:bookworm-slim AS whisper-builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates curl

ARG WHISPER_CPP_VERSION=v1.7.4
RUN git clone --depth 1 --branch "${WHISPER_CPP_VERSION}" \
      https://github.com/ggerganov/whisper.cpp /src/whisper.cpp \
 && cd /src/whisper.cpp \
 && cmake -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DWHISPER_BUILD_TESTS=OFF \
      -DWHISPER_BUILD_EXAMPLES=ON \
 && cmake --build build --config Release -j"$(nproc)" \
 && cp build/bin/whisper-cli /usr/local/bin/whisper-cpp 2>/dev/null \
    || cp build/bin/main /usr/local/bin/whisper-cpp \
 && strip /usr/local/bin/whisper-cpp

# Pre-download GGML model (cached in its own layer).
# base (~148 MB) — good balance of speed and accuracy for real-time use.
# Override at build time: --build-arg WHISPER_MODEL=tiny|small|medium|large
ARG WHISPER_MODEL=base
RUN mkdir -p /opt/whisper-models \
 && curl -fSL \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${WHISPER_MODEL}.bin" \
      -o "/opt/whisper-models/ggml-${WHISPER_MODEL}.bin" \
 && echo "${WHISPER_MODEL}" > /opt/whisper-models/.default-model


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 2: runtime
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM node:22-bookworm-slim AS base

# ── 1. System packages (rarely changes → excellent cache hit rate) ──────────
# chromium:  headless browser for agent skills (Puppeteer/Playwright)
# ffmpeg:    audio/video processing (transcoding for whisper-cpp input)
# libgomp1:  OpenMP runtime for whisper.cpp multi-threaded inference
# sqlite3:   SQLite CLI + libs for QMD local search index
# tini:      proper PID 1 for signal forwarding
# jq:        JSON processing in entrypoint for env-based config patching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      chromium \
      curl \
      ffmpeg \
      git \
      gnupg \
      gosu \
      jq \
      libgomp1 \
      sqlite3 \
      tini \
 && rm -rf /var/lib/apt/lists/*

# ── 2. Browser automation env ───────────────────────────────────────────────
ENV CHROMIUM_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright

# ── 3. OpenClaw + Clawhub + QMD (changes on version bump → separate layer) ─
ARG OC_VERSION=2026.2.6-3
RUN --mount=type=cache,target=/root/.npm \
    npm install -g "openclaw@${OC_VERSION}" clawhub @tobilu/qmd

# ── 4. Filesystem layout ───────────────────────────────────────────────────
RUN mkdir -p \
      /home/node/.openclaw/workspace/{memory,skills,canvas} \
      /home/node/.openclaw/{skills,agents/main/sessions,credentials,sandboxes,canvas,cron} \
      /home/node/.cache/{ms-playwright,qmd/models} \
      /.clawhub \
      /opt/clawos/{config,defaults/workspace,models/whisper} \
      /run/configs \
 && chown -R node:node \
      /home/node/.openclaw /home/node/.cache /.clawhub /opt/clawos /run/configs

# ── 5. Pre-bake managed skills (biggest startup win) ───────────────────────
# Skills are installed at BUILD time so containers start instantly.
# The manifest is copied first in its own layer — changing config files
# later won't invalidate this expensive layer.
COPY config/skills-manifest.txt /opt/clawos/config/skills-manifest.txt
RUN --mount=type=cache,target=/home/node/.npm,uid=1000,gid=1000 \
    chown node:node /opt/clawos/config/skills-manifest.txt \
 && su node -c '\
      set -e; \
      cd /home/node/.openclaw; \
      while IFS= read -r line || [ -n "$line" ]; do \
        name="$(printf "%s" "$line" | sed "s/#.*//;s/[[:space:]]//g")"; \
        [ -z "$name" ] && continue; \
        echo "[build] pre-installing skill: $name"; \
        clawhub install "$name" 2>&1 || echo "[build] warning: $name install failed (non-fatal)"; \
      done < /opt/clawos/config/skills-manifest.txt \
    '

# ── 6. whisper.cpp binary + GGML model (from builder stage) ────────────────
# Binary: /usr/local/bin/whisper-cpp
# Models: /opt/clawos/models/whisper/ggml-{model}.bin
COPY --from=whisper-builder /usr/local/bin/whisper-cpp /usr/local/bin/whisper-cpp
COPY --from=whisper-builder /opt/whisper-models/ /opt/clawos/models/whisper/
RUN chown -R node:node /opt/clawos/models

# ── 7. Config + defaults (changes often → late layer for fast rebuilds) ────
COPY config/    /opt/clawos/config/
COPY defaults/  /opt/clawos/defaults/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && chown -R node:node /opt/clawos

# ── 8. Runtime defaults ────────────────────────────────────────────────────
# All overridable at runtime via environment variables.
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
    CLAWOS_WHISPER_ENABLED=true \
    CLAWOS_WHISPER_MODEL="" \
    CLAWOS_WHISPER_THREADS="" \
    WHISPER_CPP_PATH=/usr/local/bin/whisper-cpp \
    WHISPER_MODELS_DIR=/opt/clawos/models/whisper \
    CLAWOS_QMD_ENABLED=true \
    XDG_CACHE_HOME=/home/node/.cache

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -sf http://127.0.0.1:${CLAWOS_PORT:-18789}/ || exit 1

# NOTE: no USER directive here — entrypoint starts as root to fix volume
# ownership, then drops to node via gosu before exec.
WORKDIR /home/node
EXPOSE 18789 18793

LABEL org.opencontainers.image.title="ClawOS" \
      org.opencontainers.image.description="Clawhost Agent Runtime — managed hosting for OpenClaw AI assistants" \
      org.opencontainers.image.vendor="Clawhost" \
      org.opencontainers.image.source="https://github.com/clawhost/clawos"

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
