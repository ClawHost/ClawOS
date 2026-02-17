#!/usr/bin/env bash
# Build whisper.cpp and download GGML model. Run in whisper-builder stage.
# Env: WHISPER_CPP_VERSION (default v1.8.3), WHISPER_MODEL (default base)
set -euo pipefail

WHISPER_CPP_VERSION="${WHISPER_CPP_VERSION:-v1.8.3}"
WHISPER_MODEL="${WHISPER_MODEL:-base}"

# Build binary + shared libs (GGML_NATIVE=OFF for ARM64 portability)
git clone --depth 1 --branch "${WHISPER_CPP_VERSION}" \
  https://github.com/ggml-org/whisper.cpp /src/whisper.cpp
cd /src/whisper.cpp
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DGGML_NATIVE=OFF
cmake --build build --config Release -j"$(nproc)"
cp build/bin/whisper-cli /usr/local/bin/whisper-cli
strip /usr/local/bin/whisper-cli
mkdir -p /usr/local/lib/whisper
cp -a build/src/libwhisper.so* /usr/local/lib/whisper/ 2>/dev/null || true
cp -a build/ggml/src/libggml*.so* /usr/local/lib/whisper/ 2>/dev/null || true
find build -name "*.so*" -type f -exec cp -a {} /usr/local/lib/whisper/ \; 2>/dev/null || true

# Download model
mkdir -p /opt/whisper-models
curl -fSL \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${WHISPER_MODEL}.bin" \
  -o "/opt/whisper-models/ggml-${WHISPER_MODEL}.bin"
echo "${WHISPER_MODEL}" > /opt/whisper-models/.default-model
