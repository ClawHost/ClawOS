---
name: Skillbase
version: 1.0.0
description: CLI client for searching, downloading, uploading, and managing AI skills from the Clawhost Skillbase registry
category: tools
tags: [skillbase, cli, skills, registry, automation]
---

# Skillbase CLI

Skillbase is a command-line client for the Clawhost Skillbase registry. It lets you search the public skill catalog, download skills into your workspace, upload new skills, and publish updates — all from the terminal.

Skills are reusable capabilities that extend what an AI agent can do. Each skill is a self-contained markdown document with metadata (name, version, category, tags) and a body that describes the capability. When loaded into an agent's context, a skill teaches the agent how to perform a specific task.

## Purpose

Skillbase exists so that AI agents (and their operators) can:

1. **Discover** skills from a shared public registry
2. **Install** skills into the agent's workspace to gain new capabilities
3. **Share** custom skills with the community
4. **Version** skills so agents always get the latest improvements

An agent running inside a Clawhost container can use Skillbase to dynamically extend its own functionality without redeployment — search for a skill, download it, and immediately use it.

## Requirements

- `curl` — HTTP client (pre-installed on all systems)
- `jq` — JSON processor (`apt install jq` / `brew install jq`)
- `SKILLBASE_API_TOKEN` — API key from the Clawhost dashboard (Settings > API Keys)

## Configuration

All configuration is via environment variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SKILLBASE_API_TOKEN` | Yes | — | API authentication token. Obtain from Clawhost dashboard under Settings > API Keys. Format: `sk_live_...` |
| `SKILLBASE_API_URL` | No | `https://app.clawhost.com` | API base URL. Override for self-hosted instances or local development. |
| `SKILLBASE_DIR` | No | `.` (current directory) | Base directory where skills are stored. Skills are saved to `$SKILLBASE_DIR/skills/<slug>/SKILL.md`. Inside Clawhost containers, this defaults to the OpenClaw home directory. |

## Commands

### Search for skills

```bash
skillbase search <query>
```

Search the public skill registry by name, description, or tags. Returns a formatted table with slug, version, category, name, and description.

**Examples:**

```bash
# Find browser automation skills
skillbase search browser

# Search by category
skillbase search "data extraction"

# Find skills related to a specific tool
skillbase search whisper
```

**Output:**

```
Found 3 skill(s) matching "browser":

  agent-browser  1.2.0  [automation]  Agent Browser        Browser automation and web scraping
  web-reader     1.0.0  [data]        Web Reader           Extract content from web pages
  screenshot     1.1.0  [media]       Screenshot Capture   Take screenshots of web pages
```

### List your skills

```bash
skillbase list
```

Show all skills you own (both public and private). Displays slug, version, visibility, and name.

**Output:**

```
Your skills (2):

  my-helper    v1.0.0  public   My Helper Skill
  internal-qa  v2.1.0  private  Internal QA Checklist
```

### Show skill details

```bash
skillbase info <slug>
```

Display full metadata for a skill: name, version, category, visibility, description, tags, star count, and timestamps.

**Example:**

```bash
skillbase info agent-browser
```

**Output:**

```
Agent Browser
agent-browser

  Version:       1.2.0
  Category:      automation
  Visibility:    public
  Description:   Browser automation and web scraping for AI agents
  Tags:          browser, automation, scraping
  Created:       2026-01-15T10:30:00.000Z
  Updated:       2026-02-10T14:22:00.000Z
  Stars:         12
```

### Download a skill

```bash
skillbase download [--force] <slug>
```

Download a skill from the registry and save it to `$SKILLBASE_DIR/skills/<slug>/SKILL.md`. The file includes YAML frontmatter (name, version, description, category, tags) followed by the skill content.

**Flags:**

| Flag | Description |
|------|-------------|
| `--force`, `-f` | Overwrite if the file already exists |

**Examples:**

```bash
# Download a skill
skillbase download agent-browser

# Force overwrite an existing skill
skillbase download --force agent-browser

# Download to a custom directory
SKILLBASE_DIR=/home/node/.openclaw skillbase download qmd
```

**File structure after download:**

```
skills/
  agent-browser/
    SKILL.md        # The downloaded skill file
  qmd/
    SKILL.md
```

### Upload a new skill

```bash
skillbase upload <path-to-SKILL.md>
```

Create a new skill in the registry from a local SKILL.md file. The file must have YAML frontmatter with at least a `name` field.

**Example:**

```bash
skillbase upload ./skills/my-new-skill/SKILL.md
```

**SKILL.md format:**

```markdown
---
name: My New Skill
version: 1.0.0
description: What this skill does
category: tools
tags: [automation, helper]
---

# My New Skill

Instructions for the AI agent on how to use this skill...
```

**Required frontmatter fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Human-readable skill name |
| `version` | No | Semantic version (default: `1.0.0`) |
| `description` | No | Short description of what the skill does |
| `category` | No | Category for organization (e.g., `tools`, `automation`, `data`) |
| `tags` | No | Comma-separated list in brackets: `[tag1, tag2]` |

### Update an existing skill

```bash
skillbase edit <slug> [path-to-SKILL.md]
```

Create a new version of an existing skill. If no path is given, reads from `$SKILLBASE_DIR/skills/<slug>/SKILL.md`.

**Workflow:**

```bash
# 1. Download the current version
skillbase download my-skill

# 2. Edit the file
vim skills/my-skill/SKILL.md

# 3. Bump the version in frontmatter, then push
skillbase edit my-skill
```

The `version` field in the frontmatter should be incremented (e.g., `1.0.0` to `1.1.0`).

## SKILL.md File Format

Every skill is a single markdown file with YAML frontmatter. This is the standard format used across the Clawhost ecosystem — by the Skillbase CLI, the dashboard skill editor, and the `clawhub` package manager inside agent containers.

```markdown
---
name: Skill Name
version: 1.0.0
description: Brief description of what this skill enables
category: category-name
tags: [tag1, tag2, tag3]
---

The body of the skill goes here. This is the content that gets loaded
into the AI agent's context when the skill is activated.

Write clear, actionable instructions that tell the agent:
- What capability this skill provides
- When and how to use it
- What tools or commands are available
- What the expected inputs and outputs are
- Any constraints or best practices

Use markdown formatting: headers, code blocks, lists, tables.
The agent reads this as instructions, so write in second person imperative.
```

## How AI Agents Use Skillbase

An AI agent running inside a Clawhost container can extend its own capabilities at runtime using Skillbase. The typical flow:

### 1. User requests a capability the agent doesn't have

The user asks the agent to do something it doesn't know how to do — for example, "scrape this website" or "generate a QR code."

### 2. Agent searches for a matching skill

```bash
skillbase search "web scraping"
```

The agent finds relevant skills in the public registry.

### 3. Agent downloads and activates the skill

```bash
skillbase download web-scraper
```

The skill file is saved to the agent's skills directory. The agent can then read the skill content and follow its instructions to perform the requested task.

### 4. Skill persists across sessions

Once downloaded, the skill remains in the agent's workspace. It's available in all future conversations without needing to download again.

### Self-extending agent pattern

An agent with Skillbase access can autonomously:

1. Recognize when it lacks a capability
2. Search the registry for a relevant skill
3. Download and read the skill
4. Apply the skill's instructions to complete the task
5. Optionally tell the user what new skill it learned

This creates a self-extending agent that grows more capable over time through the shared skill ecosystem.

## Writing Good Skills

When creating skills for the registry:

- **Be specific** — one skill, one capability. "Browser Automation" not "Everything Web."
- **Write for the agent** — use imperative instructions: "Use the `screenshot` tool to capture..." not "This skill provides screenshot functionality."
- **Include examples** — show the agent what inputs look like and what outputs to produce.
- **Document tools** — if the skill depends on specific CLI tools or APIs, list them with usage examples.
- **Version thoughtfully** — bump patch for fixes, minor for new features, major for breaking changes.
- **Tag accurately** — tags help agents find skills. Use specific terms, not generic ones.

## Error Handling

The CLI provides clear error messages for common issues:

| Error | Cause | Fix |
|-------|-------|-----|
| `SKILLBASE_API_TOKEN is not set` | Missing authentication | Set the env var with your API key from the dashboard |
| `API error (401): Unauthorized` | Invalid or revoked token | Generate a new key in the dashboard |
| `API error (404): Skill not found` | Slug doesn't exist or is private | Check the slug with `skillbase search` |
| `File already exists` | Skill already downloaded | Use `--force` flag to overwrite |
| `No valid YAML frontmatter` | File missing `---` delimiters | Add frontmatter block to your SKILL.md |
| `Failed to connect` | Network or URL issue | Check `SKILLBASE_API_URL` and network connectivity |

## Environment Setup for Agents

Inside a Clawhost container, Skillbase is pre-configured:

```bash
# These are set automatically in Clawhost containers:
export SKILLBASE_API_TOKEN="sk_live_..."     # Provisioned per agent
export SKILLBASE_DIR="/home/node/.openclaw"  # OpenClaw home directory

# Skills are stored at:
# /home/node/.openclaw/skills/<slug>/SKILL.md
```

For local development or external use:

```bash
# Get your API token from: https://app.clawhost.com/settings/api-keys
export SKILLBASE_API_TOKEN="sk_live_your_token_here"

# Optional: point to local dev server
export SKILLBASE_API_URL="http://localhost:3001"

# Optional: custom skills directory
export SKILLBASE_DIR="$HOME/.openclaw"
```
