#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERR=0

fail() { echo "FAIL  $1"; ERR=$((ERR + 1)); }
ok()   { echo "  ok  $1"; }

echo "── ClawOS image validation ──"

# Required layout
for f in Dockerfile entrypoint.sh \
         config/openclaw.json config/security-rules.md config/skills-manifest.txt; do
  [[ -f "$ROOT/$f" ]] && ok "$f" || fail "$f missing"
done
[[ -d "$ROOT/defaults/workspace" ]] && ok "defaults/workspace/" || fail "defaults/workspace/ missing"

# openclaw.json must be parseable
if command -v jq &>/dev/null && [[ -f "$ROOT/config/openclaw.json" ]]; then
  jq empty "$ROOT/config/openclaw.json" 2>/dev/null \
    && ok "openclaw.json valid JSON" \
    || fail "openclaw.json is not valid JSON"
fi

# Look for common API-key prefixes in source files.
# Intentionally narrow: only flag strings that resemble real keys.
echo "── secret scan ──"
HIT=0
while IFS= read -r match; do
  echo "  !! $match"
  HIT=1
done < <(
  grep -rnE '(sk-ant-api|sk-or-v1|ghp_[A-Za-z0-9]{36}|whsec_[A-Za-z0-9])' "$ROOT" \
    --include='*.json' --include='*.md' --include='*.txt' \
    --include='*.sh' --include='*.yml' --include='*.yaml' \
    --exclude='validate.sh' --exclude-dir='.git' 2>/dev/null || true
)
if [[ $HIT -eq 1 ]]; then
  fail "potential credentials in tracked files"
else
  ok "no credentials detected"
fi

echo ""
if [[ $ERR -gt 0 ]]; then
  echo "$ERR error(s) — fix before building"
  exit 1
fi
echo "all checks passed"
