###############################################################################
# OpenClaw Agent – Docker Image (Clawhost managed + BYO)
#
# Single image used for both Docker Swarm (managed) and BYO deployments.
# Runtime config is injected via Docker configs/env vars, not baked in.
###############################################################################

FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates gnupg tini jq \
  && rm -rf /var/lib/apt/lists/*

# Pin OpenClaw version for reproducible builds
ARG OPENCLAW_VERSION=2026.2.6-3
RUN npm install -g openclaw@${OPENCLAW_VERSION} clawhub

# Create OpenClaw directory structure
RUN mkdir -p /home/node/.openclaw/workspace/memory \
             /home/node/.openclaw/workspace/skills \
             /home/node/.openclaw/agents/main/sessions \
             /home/node/.openclaw/credentials \
             /home/node/.openclaw/canvas \
             /home/node/.openclaw/cron \
             /.clawhub \
  && chown -R node:node /home/node/.openclaw /.clawhub

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -sf http://127.0.0.1:18789/ || exit 1

USER node
EXPOSE 18789
ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
