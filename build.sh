#!/usr/bin/env bash
# ==============================================================================
# Build & Run script for llama.cpp Xing4.0 (PR #29012)
# ==============================================================================
set -euo pipefail

# ---- Config ----
IMAGE_NAME="llama-xing4"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
PORT="${PORT:-8080}"

# ---- Parse args ----
ACTION="${1:-build}"
shift || true

case "$ACTION" in
    # ---- Build GPU image ----
    "build"|"build-gpu")
        echo "[*] Building GPU image: ${IMAGE_NAME}"
        docker build -t "${IMAGE_NAME}" \
            -f Dockerfile.cuda \
            --build-arg GIT_URL=https://github.com/shuxiaoqiong/llama.cpp.git \
            --build-arg GIT_BRANCH=xing4_0-port \
            --build-arg GGML_CUDA=ON \
            --build-arg CUDA_ARCH="${CUDA_ARCH:-75;80;86;89;90}" \
            .
        echo "[done] Image built: ${IMAGE_NAME}"
        ;;

    # ---- Build CPU-only image ----
    "build-cpu")
        echo "[*] Building CPU image: ${IMAGE_NAME}-cpu"
        docker build -t "${IMAGE_NAME}-cpu" \
            -f Dockerfile.cpu \
            --build-arg GIT_URL=https://github.com/shuxiaoqiong/llama.cpp.git \
            --build-arg GIT_BRANCH=xing4_0-port \
            .
        echo "[done] Image built: ${IMAGE_NAME}-cpu"
        ;;

    # ---- Run on GPU ----
    # Usage: ./build.sh run <model.gguf> [extra args...]
    "run")
        MODEL="${1:?Usage: run <model.gguf> [extra args...]}"
        shift 1 || true

        echo "[*] Starting llama-server with Xing4.0"
        echo "    Model: ${MODEL}"

        docker run --rm -it \
            --gpus all \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            --shm-size 4g \
            "${IMAGE_NAME}" \
            -m "/models/${MODEL}" \
            -c "${CTX_SIZE:-32768}" \
            -ngl "${NGL:-99}" \
            -fa on \
            -ctk q8_0 -ctv q8_0 \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    # ---- Run on GPU with built-in MTP speculative decoding ----
    "run-mtp")
        MODEL="${1:?Usage: run-mtp <model.gguf> [extra args...]}"
        shift 1 || true

        docker run --rm -it \
            --gpus all \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            --shm-size 4g \
            "${IMAGE_NAME}" \
            -m "/models/${MODEL}" \
            --spec-type draft-mtp \
            --spec-draft-n-max "${SPEC_N_MAX:-4}" \
            -c "${CTX_SIZE:-32768}" \
            -ngl "${NGL:-99}" \
            -fa on \
            -ctk q8_0 -ctv q8_0 \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    # ---- Run CPU-only (slow, smoke test only) ----
    "run-cpu")
        MODEL="${1:?Usage: run-cpu <model.gguf> [extra args...]}"
        shift 1 || true

        docker run --rm -it \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            --shm-size 4g \
            "${IMAGE_NAME}-cpu" \
            -m "/models/${MODEL}" \
            -c "${CTX_SIZE:-8192}" \
            -ngl 0 \
            -fa on \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    "help"|*)
        cat << 'USAGE'
llama.cpp Xing4.0 (PR #29012) build & run script

USAGE:
  ./build.sh build           Build GPU Docker image (CUDA)
  ./build.sh build-cpu       Build CPU-only Docker image
  ./build.sh run <model> [extra...]        Run llama-server on GPU
  ./build.sh run-mtp <model> [extra...]    Run with built-in MTP spec decoding
  ./build.sh run-cpu <model> [extra...]    Run on CPU (smoke test)

ENVIRONMENT:
  MODEL_DIR   Host directory with GGUF files (default: ~/models)
  PORT        Host port mapping (default: 8080)
  CUDA_ARCH   CUDA arch, e.g. 75 (2080Ti), 89 (4090)
  SPEC_N_MAX  MTP draft depth (default: 4)
  CTX_SIZE    Context size (default: 32768; model supports up to 256K)
  NGL         GPU layers (default: 99)

XING4.0 MODEL:
  XingChen-AGI/Xing4.0-29B-A4B on HuggingFace / ModelScope
  GGUF must be converted with PR #29012 branch conversion scripts
  (general.architecture = "xing4_0"; official llama.cpp cannot load it)

KNOWN NOTES:
  - PR #29012 is under review; upstream branch may be force-pushed.
    Each build clones the branch HEAD; rebuild to pick up fixes.
  - If the PR author changes tensor names/params, old GGUF files must be
    reconverted with the updated branch.
  - CPU-only inference of a 29B MoE is very slow (smoke test only).
USAGE
        ;;
esac
