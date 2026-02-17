###############################################################################
# ClawOS — Clawhost Agent Runtime
#
# Generic image for managed (Swarm) and BYO deployments.
# User-specific configuration is injected at runtime via /run/configs/.
###############################################################################

FROM node:22-bookworm

# ── System packages ─────────────────────────────────────────────────────────
# chromium: headless browser for agent skills (Puppeteer/Playwright)
# tini:     proper PID 1 for signal forwarding
# jq:       JSON processing in entrypoint
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates chromium curl git gnupg jq tini \
 && rm -rf /var/lib/apt/lists/*

# ── Browser automation ──────────────────────────────────────────────────────
ENV CHROMIUM_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright

# ── Application layer ──────────────────────────────────────────────────────
ARG OC_VERSION=2026.2.6-3
RUN npm install -g "openclaw@${OC_VERSION}" clawhub \
 && npm cache clean --force

# ── Filesystem layout ──────────────────────────────────────────────────────
RUN set -x \
 && mkdir -p \
      /home/node/.openclaw/workspace/{memory,skills,canvas} \
      /home/node/.openclaw/{skills,agents/main/sessions,credentials,sandboxes,canvas,cron} \
      /home/node/.cache/ms-playwright \
      /.clawhub \
      /opt/clawos/{config,defaults/workspace} \
 && chown -R node:node /home/node/.openclaw /home/node/.cache /.clawhub /opt/clawos

# ── Baked-in files ──────────────────────────────────────────────────────────
COPY config/    /opt/clawos/config/
COPY defaults/  /opt/clawos/defaults/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── Runtime ─────────────────────────────────────────────────────────────────
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -sf http://127.0.0.1:18789/ || exit 1

USER node
WORKDIR /home/node
EXPOSE 18789
ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
