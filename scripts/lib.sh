#!/usr/bin/env bash
# ClawOS entrypoint library — constants and helpers.
# Sourced by entrypoint.sh; do not run directly.

OC="${OC:-/home/node/.openclaw}"
WS="${WS:-$OC/workspace}"
CFG="${CFG:-/opt/clawos/config}"
TPL="${TPL:-/opt/clawos/defaults}"
RUN_CFG="${RUN_CFG:-/run/configs}"
WHISPER_BIN="${WHISPER_CPP_PATH:-/usr/local/bin/whisper-cli}"
WHISPER_DIR="${WHISPER_MODELS_DIR:-/opt/clawos/models/whisper}"
QMD_CACHE="${XDG_CACHE_HOME:-/home/node/.cache}/qmd"

log() { printf "[clawos %s] %s\n" "$(date -u +%H:%M:%S)" "$*"; }
