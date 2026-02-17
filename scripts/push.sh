#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${IMAGE_NAME:-ghcr.io/clawhost/clawos}"
TAG="${IMAGE_TAG:-latest}"

IMAGE_NAME="$IMG" IMAGE_TAG="$TAG" "$ROOT/scripts/build.sh"
echo ""

echo "Pushing $IMG:$TAG"
docker push "$IMG:$TAG"
echo "Done"
