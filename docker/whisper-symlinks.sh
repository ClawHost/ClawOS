#!/usr/bin/env bash
# Create whisper binary and model symlinks for agent discovery. Run in base stage.
set -euo pipefail

ldconfig
ln -sf /usr/local/bin/whisper-cli /usr/local/bin/whisper
ln -sf /usr/local/bin/whisper-cli /usr/local/bin/whisper-cpp

mkdir -p /home/node/.cache/whisper /home/node/models /home/node/.openclaw/workspace
for name in ggml-base.bin base.en base; do
  ln -sf /opt/clawos/models/whisper/ggml-base.bin "/home/node/.cache/whisper/$name"
  ln -sf /opt/clawos/models/whisper/ggml-base.bin "/home/node/models/$name"
done
ln -sf /opt/clawos/models/whisper /home/node/.whisper
ln -sf /opt/clawos/models/whisper/ggml-base.bin /home/node/.openclaw/workspace/base.en
ln -sf /opt/clawos/models/whisper/ggml-base.bin /home/node/.openclaw/workspace/base
ln -sf /opt/clawos/models/whisper/ggml-base.bin /home/node/.openclaw/workspace/ggml-base.bin
ln -sf /opt/clawos/models/whisper/ggml-base.bin /home/node/.openclaw/workspace/ggml-base.en.bin

chown -R node:node /opt/clawos/models /home/node/.cache/whisper /home/node/models /home/node/.whisper /home/node/.openclaw
