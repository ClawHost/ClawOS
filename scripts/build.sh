#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${IMAGE_NAME:-clawos}"
TAG="${IMAGE_TAG:-latest}"

"$ROOT/scripts/validate.sh"
echo ""

echo "Building $IMG:$TAG"
docker build -t "$IMG:$TAG" -f "$ROOT/Dockerfile" "$ROOT"

echo ""
echo "Done — run with:"
echo "  docker run --rm -it $IMG:$TAG"
