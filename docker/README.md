# Docker build assets

- **whisper-build.sh** — Stage 1: build whisper.cpp and download GGML model. Uses `WHISPER_CPP_VERSION`, `WHISPER_MODEL`.
- **whisper-symlinks.sh** — Stage 2: `ldconfig` + binary/model symlinks for agent discovery.
- **env.vars** — List of runtime ENV names (documentation; Dockerfile ENV block is source of truth).

Build: from repo root, `docker build -f Dockerfile .` (or use BuildKit).
