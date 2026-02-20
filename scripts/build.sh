#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${IMAGE_NAME:-clawos}"
TAG="${IMAGE_TAG:-latest}"
PLATFORM="${IMAGE_PLATFORM:-linux/amd64}"

"$ROOT/scripts/validate.sh"
echo ""

echo "Building $IMG:$TAG (platform: $PLATFORM)"
DOCKER_BUILDKIT=1 docker build \
  --platform "$PLATFORM" \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t "$IMG:$TAG" \
  -f "$ROOT/Dockerfile" \
  "$ROOT"

echo ""
echo "Done — run with:"
echo "  docker run --rm -it -e OPENCLAW_GATEWAY_TOKEN=test $IMG:$TAG"
echo ""
echo "Run with config overrides:"
echo "  docker run --rm -it \\"
echo "    -e OPENCLAW_GATEWAY_TOKEN=test \\"
echo "    -e CLAWOS_MODEL=anthropic/claude-sonnet-4-5 \\"
echo "    -e CLAWOS_PORT=18789 \\"
echo "    $IMG:$TAG"
