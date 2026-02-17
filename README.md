# ClawOS

Clawhost agent runtime image. Every deployed agent runs inside this container.

## Layout

```
config/
  openclaw.json          Platform default gateway configuration
  security-rules.md      Mandatory rules written to SECURITY.md every boot
  skills-manifest.txt    Managed skills installed to ~/.openclaw/skills/
defaults/
  workspace/
    TOOLS.md             Baseline workspace file (seeded once, not overwritten)
scripts/
  validate.sh            Pre-build checks (structure + credential scan)
  build.sh               Local image build
  push.sh                Build + push to GHCR
Dockerfile               Image definition
entrypoint.sh            Boot sequence
```

## How Configuration Reaches the Container

The provisioner creates Docker configs (Swarm) or bind mounts (BYO) at:

```
/run/configs/
  openclaw.json      Agent-specific gateway config
  workspace/         SOUL.md, IDENTITY.md, USER.md, AGENTS.md, …
  env                Shell-sourceable secrets (OPENCLAW_GATEWAY_TOKEN, etc.)
```

If no provisioner config is mounted, the image falls back to `config/openclaw.json`.

## Boot Sequence

1. **Provisioner config** — `/run/configs/*` copied into `~/.openclaw/`; falls back to baked-in default
2. **Workspace templates** — `defaults/workspace/*` seeded with `cp -n` (first boot only)
3. **Security rules** — `config/security-rules.md` → `workspace/SECURITY.md` (every boot)
4. **Managed skills** — entries in `config/skills-manifest.txt` installed to `~/.openclaw/skills/`

## Directory Tree Inside the Container

```
/home/node/.openclaw/
  openclaw.json               gateway config (provisioner or default)
  workspace/
    SECURITY.md               platform boundaries (overwritten each boot)
    TOOLS.md                  baseline tool guidance (first boot only)
    memory/                   daily memory logs
    skills/                   user-level skill overrides (highest priority)
    canvas/
  skills/                     managed skills from manifest (middle priority)
  agents/main/sessions/
  credentials/
  sandboxes/
  canvas/
  cron/
```

## Scripts

```bash
bash scripts/validate.sh    # structure + secret scan
bash scripts/build.sh       # docker build
bash scripts/push.sh        # build + docker push
```

Override image coordinates:

```bash
IMAGE_NAME=ghcr.io/clawhost/clawos IMAGE_TAG=v2 bash scripts/push.sh
```
