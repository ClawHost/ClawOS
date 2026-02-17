# ClawOS

Clawhost agent runtime image. Every deployed agent runs inside this container.

## Design Goals

- **Instant deploy** — managed skills (browser, monitor, whisper, qmd) and system deps (ffmpeg, chromium, whisper-cli, sqlite3) are pre-baked at build time. Container boot is sub-second config injection + exec.
- **Fast rebuilds** — multi-stage BuildKit build with cache mounts for apt, npm, and cmake. Config file changes don't invalidate expensive compilation or skill layers.
- **Local voice processing** — whisper.cpp compiled from source with a pre-downloaded GGML model. Speech-to-text runs entirely on-device with zero API calls.
- **Local search** — [QMD](https://github.com/tobi/qmd) provides hybrid BM25 + vector search over the agent's workspace. Keyword search works instantly; semantic search uses local GGUF models.
- **Fully configurable** — every runtime parameter (model, port, context tokens, timeout, whisper model, etc.) is overridable via environment variables without mounting a full config file.

## Layout

```
config/
  openclaw.json          Platform default gateway configuration
  security-rules.md      Mandatory rules written to SECURITY.md every boot
  skills-manifest.txt    Managed skills pre-installed at build time
defaults/
  workspace/
    TOOLS.md             Baseline workspace file (seeded once, not overwritten)
scripts/
  validate.sh            Pre-build checks (structure + credential scan)
  build.sh               Local image build (BuildKit)
  push.sh                Build + push to GHCR
Dockerfile               Multi-stage image (whisper-builder → runtime)
entrypoint.sh            Boot sequence
```

## What's Baked Into the Base Image

| Component           | Purpose                                                           |
| ------------------- | ----------------------------------------------------------------- |
| OpenClaw + Clawhub  | Agent runtime and skill manager                                   |
| Chromium            | Headless browser for agent-browser skill                          |
| ffmpeg              | Audio/video transcoding (pre-processes audio for whisper-cli)     |
| whisper-cli         | Local speech-to-text via whisper.cpp (compiled, no Python needed) |
| GGML model (`base`) | Pre-downloaded whisper model (~148 MB, configurable at build)     |
| libgomp1            | OpenMP runtime for whisper-cli multi-threaded inference           |
| QMD (`@tobilu/qmd`) | Local hybrid search (BM25 + vector + LLM re-ranking)              |
| sqlite3             | SQLite CLI + extension support for QMD index                      |
| agent-browser       | Web browsing capability (pre-baked skill)                         |
| system-monitor      | System monitoring (pre-baked skill)                               |
| whisper             | Whisper integration skill (pre-baked skill)                       |
| qmd                 | QMD search skill (pre-baked skill)                                |

## Multi-Stage Build

```
┌─────────────────────┐    ┌─────────────────────────────────────┐
│  whisper-builder     │    │  base (runtime)                     │
│                      │    │                                     │
│  debian:bookworm-slim│    │  node:22-bookworm-slim              │
│  cmake + g++         │    │  chromium, ffmpeg, sqlite3, tini    │
│  compile whisper.cpp │    │  openclaw + clawhub + qmd           │
│  download GGML model │    │  pre-bake managed skills            │
│                      │    │                                     │
│  ┌─────────────────┐ │    │  COPY ← whisper-cli binary           │
│  │ whisper-cli bin  │─┼───│  COPY ← ggml-base.bin model         │
│  │ ggml-base.bin    │ │    │                                     │
│  └─────────────────┘ │    │  config + defaults + entrypoint     │
└─────────────────────┘    └─────────────────────────────────────┘
        (parallel)                    (parallel until COPY)
```

BuildKit builds both stages in parallel. The builder compiles whisper.cpp while the runtime installs system packages and npm globals. They join at the `COPY --from=whisper-builder` step. No compile tools (cmake, g++, build-essential) end up in the final image.

## How Configuration Reaches the Container

### Option 1: Environment Variables (fastest)

Override individual settings without mounting files:

```bash
docker run --rm \
  -e OPENCLAW_GATEWAY_TOKEN=tok_xxx \
  -e CLAWOS_MODEL=anthropic/claude-sonnet-4-5 \
  -e CLAWOS_PORT=18789 \
  -e CLAWOS_CONTEXT_TOKENS=200000 \
  -e CLAWOS_MAX_CONCURRENT=5 \
  -e CLAWOS_TIMEOUT=900 \
  -e CLAWOS_LOG_LEVEL=debug \
  -e CLAWOS_TOOLS_PROFILE=full \
  -e CLAWOS_SANDBOX_MEMORY=1g \
  -e CLAWOS_COMPACTION_MODE=aggressive \
  -e CLAWOS_WHISPER_MODEL=base \
  -e CLAWOS_WHISPER_THREADS=4 \
  -e CLAWOS_QMD_ENABLED=true \
  -e CLAWOS_EXTRA_SKILLS="custom-skill,another-skill" \
  ghcr.io/clawhost/clawos
```

### Option 2: Mounted Config (full control)

The provisioner creates Docker configs (Swarm) or bind mounts (BYO) at:

```
/run/configs/
  openclaw.json      Agent-specific gateway config (overrides baked default)
  workspace/         SOUL.md, IDENTITY.md, USER.md, AGENTS.md, …
  env                Shell-sourceable secrets (OPENCLAW_GATEWAY_TOKEN, etc.)
  qmd-collections.sh Optional script to register extra QMD collections
```

### Option 3: Both

Mount a base config + patch specific fields via env vars. Env vars are applied after config file loading.

## Environment Variables Reference

### Model Provider API Keys

Set **one** of these to authenticate with an LLM provider. OpenRouter routes all models through a single key; direct keys go straight to the provider API.

| Variable               | Provider                       | Models                          |
| ---------------------- | ------------------------------ | ------------------------------- |
| `OPENROUTER_API_KEY`   | OpenRouter (routes all models) | All models via single key       |
| `ANTHROPIC_API_KEY`    | Anthropic                      | Claude Opus, Sonnet, Haiku      |
| `OPENAI_API_KEY`       | OpenAI                         | GPT-4o, o1, o3, GPT-4 Turbo     |
| `GOOGLE_API_KEY`       | Google                         | Gemini 2.5 Pro/Flash, Ultra     |
| `GROQ_API_KEY`         | Groq                           | Llama, Mixtral (fast inference) |
| `MISTRAL_API_KEY`      | Mistral                        | Mistral Large, Medium, Small    |
| `DEEPSEEK_API_KEY`     | DeepSeek                       | DeepSeek V3, R1                 |
| `XAI_API_KEY`          | xAI                            | Grok 3, Grok 4                  |
| `COHERE_API_KEY`       | Cohere                         | Command R, Command R+           |
| `TOGETHER_API_KEY`     | Together AI                    | Llama, Mixtral, DBRX            |
| `FIREWORKS_API_KEY`    | Fireworks AI                   | Llama, Mixtral (fast inference) |
| `CEREBRAS_API_KEY`     | Cerebras                       | Llama (fastest inference)       |
| `AI21_API_KEY`         | AI21 Labs                      | Jamba 1.5                       |
| `GITHUB_COPILOT_TOKEN` | GitHub Copilot                 | Copilot models (token auth)     |

### Tool / Service Keys (Optional)

These are read automatically by OpenClaw tools and TTS. No auth profile needed — just pass the env var.

| Variable             | Service      | Used By                                   |
| -------------------- | ------------ | ----------------------------------------- |
| `PERPLEXITY_API_KEY` | Perplexity   | `tools.webSearch` (provider="perplexity") |
| `BRAVE_API_KEY`      | Brave Search | `tools.webSearch` (provider="brave")      |
| `FIRECRAWL_API_KEY`  | Firecrawl    | `tools.webSearch` scraper fallback        |
| `ELEVENLABS_API_KEY` | ElevenLabs   | TTS voice synthesis                       |

### Channels (IM / messaging)

Set the env var(s) for the channel; the entrypoint enables the channel and plugin and injects tokens into `env.vars`. OpenClaw supports many channels; these are the ones wired by env in ClawOS:

| Variable                     | Channel  | Notes                                                                                                                               |
| ---------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `TELEGRAM_BOT_TOKEN`         | Telegram | Bot token from [@BotFather](https://t.me/BotFather). Enables channel + plugin.                                                      |
| `CLAWOS_TELEGRAM_ALLOW_FROM` | Telegram | Comma-separated Telegram user IDs (e.g. `475658119`). Those users can DM the bot without pairing; `dmPolicy` is set to `allowlist`. |
| `DISCORD_BOT_TOKEN`          | Discord  | Bot token from [Discord Developer Portal](https://discord.com/developers/applications).                                             |
| `SLACK_BOT_TOKEN`            | Slack    | Bot User OAuth Token (Socket Mode).                                                                                                 |
| `SLACK_APP_TOKEN`            | Slack    | App-level token (e.g. `xapp-...`); often required with bot token.                                                                   |
| `CLAWOS_WHATSAPP_ENABLED`    | WhatsApp | Set to `true` to enable; no token — pair via QR at runtime (Baileys).                                                               |

**Policies**: Telegram uses `dmPolicy: pairing`, `groupPolicy: allowlist`. Discord/Slack use `dm.policy: pairing`. To change policies or add allowlists, mount a custom `openclaw.json` at `/run/configs/openclaw.json` or use a provisioner-generated config.

**Other channels** (IRC, Signal, Feishu, Google Chat, Mattermost, LINE, Microsoft Teams, etc.) may require a plugin install or full channel config; use `CLAWOS_EXTRA_SKILLS` or mount config from the provisioner.

**OpenRouter mode**: when `OPENROUTER_API_KEY` is set, the entrypoint automatically:

- Registers `openrouter:manual` auth profile
- Adds `models.providers.openrouter` with the OpenRouter base URL
- Prefixes the model ID with `openrouter/` (e.g., `anthropic/claude-sonnet-4-5` → `openrouter/anthropic/claude-sonnet-4-5`)

**Direct mode**: when a provider-specific key is set, the entrypoint:

- Registers `<provider>:manual` auth profile (e.g., `anthropic:manual`)
- Adds `env.vars.<KEY>` for OpenClaw to pick up
- Model ID used as-is

### Agent Configuration

| Variable                 | What it patches                          | Example                       |
| ------------------------ | ---------------------------------------- | ----------------------------- |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway auth token                       | `tok_xxx`                     |
| `CLAWOS_MODEL`           | `agents.defaults.model.primary`          | `anthropic/claude-sonnet-4-5` |
| `CLAWOS_CONTEXT_TOKENS`  | `agents.defaults.contextTokens`          | `200000`                      |
| `CLAWOS_MAX_CONCURRENT`  | `agents.defaults.maxConcurrent`          | `3`                           |
| `CLAWOS_TIMEOUT`         | `agents.defaults.timeoutSeconds`         | `600`                         |
| `CLAWOS_PORT`            | `gateway.port`                           | `18789`                       |
| `CLAWOS_LOG_LEVEL`       | `logging.level` + `logging.consoleLevel` | `info`, `debug`               |
| `CLAWOS_TOOLS_PROFILE`   | `tools.profile`                          | `full`, `minimal`             |
| `CLAWOS_SANDBOX_MEMORY`  | `agents.defaults.sandbox.docker.memory`  | `512m`, `1g`                  |
| `CLAWOS_COMPACTION_MODE` | `agents.defaults.compaction.mode`        | `safeguard`, `aggressive`     |

### whisper-cli (Local Voice Processing)

Speech-to-text is handled by `whisper-cli` via `tools.media.audio` (not a skill).
The binary and model are baked into the image.

| Variable                 | What it patches                         | Default                      | Example                   |
| ------------------------ | --------------------------------------- | ---------------------------- | ------------------------- |
| `CLAWOS_WHISPER_MODEL`   | `tools.media.audio.models[0]` model path | `base`                       | `tiny`, `small`, `medium` |
| `CLAWOS_WHISPER_THREADS` | `tools.media.audio.models[0]` threads    | `4`                          | `2`, `8`                  |
| `WHISPER_CPP_PATH`       | Binary location (env reference)          | `/usr/local/bin/whisper-cli` | —                         |
| `WHISPER_MODELS_DIR`     | Models directory (env reference)         | `/opt/clawos/models/whisper` | —                         |

**Note:** The `whisper` skill in clawhub is for encrypted agent-to-agent communication,
not speech-to-text. ClawOS uses the native `tools.media.audio` CLI integration instead.

### QMD (Local Search)

| Variable             | What it patches                      | Default             | Example            |
| -------------------- | ------------------------------------ | ------------------- | ------------------ |
| `CLAWOS_QMD_ENABLED` | `skills.entries.qmd.enabled`         | `true`              | `false` to disable |
| `XDG_CACHE_HOME`     | Skill env: QMD cache/index directory | `/home/node/.cache` | —                  |

### TTS (Text-to-Speech)

Edge TTS is enabled by default — free, no API key required, 40+ languages.

| Variable              | What it patches           | Default            | Example                              |
| --------------------- | ------------------------- | ------------------ | ------------------------------------ |
| `CLAWOS_TTS_AUTO`     | `messages.tts.auto`       | `inbound`          | `off`, `always`, `inbound`, `tagged` |
| `CLAWOS_TTS_PROVIDER` | `messages.tts.provider`   | `edge`             | `edge`, `openai`, `elevenlabs`       |
| `CLAWOS_TTS_VOICE`    | `messages.tts.edge.voice` | `en-US-AriaNeural` | Any Edge voice                       |

**Auto modes:**

- `off` — TTS disabled
- `always` — All replies are spoken
- `inbound` — Reply with voice when user sends voice (recommended)
- `tagged` — Only speak when model uses TTS tags

**Popular Edge voices:**

- English: `en-US-AriaNeural`, `en-US-GuyNeural`, `en-GB-SoniaNeural`
- Spanish: `es-ES-ElviraNeural`, `es-MX-DaliaNeural`
- French: `fr-FR-DeniseNeural`
- German: `de-DE-KatjaNeural`
- Chinese: `zh-CN-XiaoxiaoNeural`
- [Full list](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support)

### Skills & Verification

| Variable               | Description                          | Default |
| ---------------------- | ------------------------------------ | ------- |
| `CLAWOS_EXTRA_SKILLS`  | Additional skills to install at boot | `""`    |
| `CLAWOS_VERIFY_SKILLS` | Verify pre-baked skills on boot      | `false` |

## QMD — Local Hybrid Search

[QMD](https://github.com/tobi/qmd) (Query Markup Documents) is an on-device search engine that combines BM25 full-text search, vector semantic search, and LLM re-ranking — all running locally via GGUF models.

### What the agent gets

The `qmd` skill gives the agent these search capabilities over its own workspace:

| Command       | Mode             | Speed                   | When to use                                      |
| ------------- | ---------------- | ----------------------- | ------------------------------------------------ |
| `qmd search`  | BM25 keyword     | Instant                 | Default — keyword matches in notes, memory, docs |
| `qmd vsearch` | Vector semantic  | ~1 min cold / fast warm | When keywords fail, needs meaning-based matching |
| `qmd query`   | Hybrid + re-rank | Slowest                 | Best quality, explicit user request only         |
| `qmd get`     | Retrieve doc     | Instant                 | Fetch a specific document by path or ID          |

### Auto-indexing

On first boot, the entrypoint automatically:

1. Registers the workspace as a QMD collection (`qmd collection add`)
2. Adds context metadata for better search relevance
3. Runs `qmd update` to build the BM25 index

This means `qmd search` works immediately. No GGUF models are downloaded for keyword search.

### Semantic search models

Vector search (`vsearch`) and hybrid search (`query`) use local GGUF models that auto-download on first use:

| Model                           | Size    | Purpose           |
| ------------------------------- | ------- | ----------------- |
| embeddinggemma-300M-Q8_0        | ~300 MB | Vector embeddings |
| qwen3-reranker-0.6b-q8_0        | ~640 MB | Re-ranking        |
| qmd-query-expansion-1.7B-q4_k_m | ~1.1 GB | Query expansion   |

Models cache in `~/.cache/qmd/models/` and persist across container restarts when using a volume.

### Provisioner QMD collections

The provisioner can mount a script at `/run/configs/qmd-collections.sh` to register additional collections beyond the workspace:

```bash
#!/usr/bin/env bash
# /run/configs/qmd-collections.sh
qmd collection add /home/node/.openclaw/workspace/memory --name memory --mask "**/*.md"
qmd context add qmd://memory "Agent memory logs and daily reflections"
qmd update
```

### Disabling QMD

Set `CLAWOS_QMD_ENABLED=false` to skip workspace indexing and disable the QMD skill. The binary remains in the image.

## whisper-cli Details

### Available Models

Build with a different model using `--build-arg WHISPER_MODEL=<name>`:

| Model    | Size    | Speed   | Accuracy | Best For                                   |
| -------- | ------- | ------- | -------- | ------------------------------------------ |
| `tiny`   | ~75 MB  | Fastest | Lower    | Quick transcription, low-resource VPS      |
| `base`   | ~148 MB | Fast    | Good     | **Default** — real-time use, good balance  |
| `small`  | ~466 MB | Medium  | Better   | Higher accuracy when latency is acceptable |
| `medium` | ~1.5 GB | Slower  | High     | Premium tiers needing accuracy             |
| `large`  | ~3 GB   | Slowest | Highest  | Maximum accuracy (requires ≥4 GB RAM)      |

### Adding Extra Models at Runtime

Mount additional GGML models into the models directory:

```bash
docker run --rm \
  -v /path/to/ggml-small.bin:/opt/clawos/models/whisper/ggml-small.bin:ro \
  -e CLAWOS_WHISPER_MODEL=small \
  ghcr.io/clawhost/clawos
```

### Audio Pipeline

```
audio input (any format)
    │
    ▼
  ffmpeg (transcode to 16kHz mono WAV)
    │
    ▼
  whisper-cli (local inference, no API calls)
    │
    ▼
  text output
```

ffmpeg handles format conversion. whisper-cli expects 16 kHz mono WAV — the whisper skill handles this conversion automatically using ffmpeg.

## Boot Sequence

1. **Source env** — `/run/configs/env` loaded first (makes vars available for patching)
2. **Gateway config** — `/run/configs/openclaw.json` or baked default copied to `~/.openclaw/`
3. **Config patching** — `CLAWOS_*` env vars applied via jq (sub-50ms)
4. **Auth wiring** — API key env vars → auth profiles + model provider config
5. **Channel wiring** — TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, Slack, WhatsApp → channels + plugins
6. **Workspace files** — runtime overrides from `/run/configs/workspace/`, then first-boot template seeding
7. **Security rules** — `SECURITY.md` overwritten every boot (not user-editable)
8. **Extra skills** — `CLAWOS_EXTRA_SKILLS` installed if set (skips already-present)
9. **whisper-cli check** — logs model, binary path, and availability
10. **QMD check** — logs version; auto-indexes workspace on first boot
11. **Launch** — `exec openclaw gateway`

Steps 1–5 complete in under 200ms. Steps 9–10 are status checks (instant if index exists).

## Directory Tree Inside the Container

```
/usr/local/bin/
  whisper-cli                 whisper.cpp CLI binary (compiled at build time)
  qmd                         QMD search engine (installed via npm)

/opt/clawos/
  config/                     baked-in defaults (read-only reference)
  defaults/                   first-boot templates
  models/
    whisper/
      ggml-base.bin           pre-downloaded whisper GGML model
      .default-model          records which model was baked in

/home/node/.cache/
  qmd/
    index.sqlite              QMD search index (BM25 + metadata)
    models/                   GGUF models for semantic search (auto-downloaded)

/home/node/.openclaw/
  openclaw.json               gateway config (patched from env + mounted)
  workspace/
    SECURITY.md               platform boundaries (overwritten each boot)
    TOOLS.md                  baseline tool guidance (first boot only)
    SOUL.md                   agent soul/personality (from provisioner)
    IDENTITY.md               agent identity (from provisioner)
    memory/                   daily memory logs
    skills/                   user-level skill overrides (highest priority)
    canvas/
  skills/                     managed skills — pre-baked (middle priority)
  agents/main/sessions/
  credentials/
  sandboxes/
  canvas/
  cron/
```

## Scripts

```bash
bash scripts/validate.sh    # structure + secret scan
bash scripts/build.sh       # docker build (BuildKit)
bash scripts/push.sh        # build + docker push
```

Override image coordinates:

```bash
IMAGE_NAME=ghcr.io/clawhost/clawos IMAGE_TAG=v2 bash scripts/push.sh
```

## Build Args

| Arg                   | Default     | Purpose                                                                 |
| --------------------- | ----------- | ----------------------------------------------------------------------- |
| `OC_VERSION`          | `2026.2.15` | OpenClaw npm package version                                            |
| `WHISPER_CPP_VERSION` | `v1.7.4`    | whisper.cpp git tag to compile                                          |
| `WHISPER_MODEL`       | `base`      | GGML model to pre-download (`tiny`, `base`, `small`, `medium`, `large`) |

```bash
# Build with small whisper model and specific OpenClaw version
docker build \
  --build-arg OC_VERSION=2026.2.15 \
  --build-arg WHISPER_MODEL=small \
  --build-arg WHISPER_CPP_VERSION=v1.7.4 \
  -t clawos:next .
```

## Build Optimization Notes

- **Multi-stage parallelism**: whisper-builder compiles whisper.cpp while the runtime stage installs system packages and npm globals. BuildKit runs both in parallel until the COPY join.
- **BuildKit cache mounts**: apt, npm, and cmake caches persist across builds. Rebuilds that only change config files skip everything expensive.
- **Layer ordering**: System deps → npm globals (openclaw + clawhub + qmd) → skills → whisper binary/model → config files. Each layer only rebuilds when its inputs change.
- **Slim base**: `node:22-bookworm-slim` saves ~300MB over full `bookworm`. No compile tools in the final image (cmake, g++, build-essential stay in the builder).
- **Binary stripping**: whisper-cli binary is `strip`ped in the builder stage, reducing it by ~60%.
- **Pre-baked skills**: Skills from `config/skills-manifest.txt` are installed at build time. No network calls at boot.
- **QMD BM25 instant**: Keyword search works immediately without downloading any models. Semantic search models download lazily on first use.
- **Healthcheck start-period**: 20s (boot is near-instant since everything is pre-baked).
