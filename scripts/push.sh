#!/usr/bin/env bash
set -euo pipefail

# Push to GHCR: log in first with a GitHub PAT that has write:packages:
#   echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
# Or: docker login ghcr.io  (then enter GitHub username + PAT as password)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${IMAGE_NAME:-ghcr.io/clawhost/clawos}"
TAG="${IMAGE_TAG:-latest}"

IMAGE_NAME="$IMG" IMAGE_TAG="$TAG" "$ROOT/scripts/build.sh"
echo ""

echo "Pushing $IMG:$TAG"
docker push "$IMG:$TAG"

# Tag as cache source for future builds
if [[ "$TAG" != "latest" ]]; then
  echo "Also tagging as latest for cache"
  docker tag "$IMG:$TAG" "$IMG:latest"
  docker push "$IMG:latest"
fi

echo "Done"
