#!/usr/bin/env bash
# Eight.ly Forge - Linux installer (wrapper). Heavy lifting in Shared/install-lib.sh.
# Detects NVIDIA CUDA, AMD ROCm (incl. Strix Halo / Ryzen AI MAX iGPU), and
# falls back to CPU. Ollama's Linux tarball is unified — the same binary
# auto-detects CUDA or ROCm based on the libraries present on the host.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(cd .. && pwd)"
SHARED="$ROOT/Shared"
BIN="$SHARED/bin"
MODELS="$SHARED/models"
OLLAMA_DATA="$MODELS/ollama_data"
CATALOG="$SHARED/catalog.json"
STATE="$SHARED/install-state.json"
mkdir -p "$BIN" "$MODELS" "$OLLAMA_DATA"

command -v python3 >/dev/null 2>&1 || { echo "python3 not found. Install with: apt install python3  (or equivalent)"; exit 1; }
command -v curl    >/dev/null 2>&1 || { echo "curl not found. Install with: apt install curl"; exit 1; }
command -v tar     >/dev/null 2>&1 || { echo "tar not found."; exit 1; }
[[ -f "$CATALOG" ]] || { echo "Missing $CATALOG"; exit 2; }
# shellcheck disable=SC1090
source "$SHARED/install-lib.sh"

ely_banner "Eight.ly Forge Setup (Linux)"

# ---------- Platform detection (Linux-specific) ----------
ely_step 1 "Detecting hardware"
CPU_NAME=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | sed 's/^[^:]*: //' || echo 'unknown')
BACKEND_KEY="linux-cpu"
GPU_NAME="$CPU_NAME"

# NVIDIA: nvidia-smi is the authoritative signal; it's only present when the
# driver is installed and working.
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  BACKEND_KEY="linux-nvidia"
  GPU_NAME=$(nvidia-smi -L 2>/dev/null | head -1 | sed 's/^GPU [0-9]*: //; s/ (UUID.*$//')
else
  # AMD: amdgpu module loaded + a Radeon/Strix device visible via lspci.
  STRIX_HALO=0
  if echo "$CPU_NAME" | grep -qE 'Ryzen AI MAX'; then
    STRIX_HALO=1
  fi
  AMD_GPU=""
  if command -v lspci >/dev/null 2>&1; then
    AMD_GPU=$(lspci | grep -iE 'VGA|3D|Display' | grep -iE 'AMD|ATI|Radeon' | head -1 | sed 's/^[^:]*: //')
  fi
  AMDGPU_LOADED=0
  lsmod 2>/dev/null | grep -q '^amdgpu' && AMDGPU_LOADED=1
  if [[ -n "$AMD_GPU" && "$AMDGPU_LOADED" == "1" ]] || [[ "$STRIX_HALO" == "1" ]]; then
    BACKEND_KEY="linux-amd"
    if [[ "$STRIX_HALO" == "1" ]]; then
      GPU_NAME="${AMD_GPU:-AMD Radeon (Strix Halo iGPU)}  (Ryzen AI MAX - up to ~96 GB VRAM, gfx1151)"
    else
      GPU_NAME="${AMD_GPU}"
    fi
    # Warn on missing ROCm libs — Ollama will run CPU even with amdgpu loaded if rocm-libs are absent.
    if ! ldconfig -p 2>/dev/null | grep -q libamdhip64; then
      ely_info "amdgpu is loaded but rocm-libs were not found — install rocm-libs to enable GPU inference."
      ely_info "Ubuntu/Debian: sudo apt install rocm-libs. Strix Halo may need HSA_OVERRIDE_GFX_VERSION=11.5.1."
    fi
  fi
fi

export BACKEND_KEY GPU_NAME
ely_ok "CPU: $CPU_NAME"
if [[ "$BACKEND_KEY" != "linux-cpu" ]]; then
  ely_ok "GPU: $GPU_NAME"
fi

BACKEND_LABEL=$(ely_j "backends.$BACKEND_KEY.label")
BACKEND_URL=$(  ely_j "backends.$BACKEND_KEY.url")
BACKEND_ENTRY=$(ely_j "backends.$BACKEND_KEY.entrypoint")
ely_info "Backend: $BACKEND_LABEL"

BACKEND_DIR="$BIN/$BACKEND_KEY"
ENTRY="$BACKEND_DIR/$BACKEND_ENTRY"

# ---------- Engine install (tgz on Linux) ----------
ely_step 2 "Installing engine"
if [[ -x "$ENTRY" ]]; then
  ely_ok "Engine already present"
else
  mkdir -p "$BACKEND_DIR"
  archive="$BACKEND_DIR/_download.tgz"
  ely_info "Downloading $BACKEND_URL"
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    # -C - resumes from the last byte if a prior attempt left a partial file.
    curl $CURL_OPTS -C - "$BACKEND_URL" -o "$archive" && break
    (( attempt >= 3 )) && { ely_fail "Engine download failed"; exit 4; }
    ely_info "Attempt $attempt failed, retrying..."; sleep 2
  done
  # Size sanity (catalog may publish sizeBytes for the engine).
  EXPECTED=$(python3 -c "import json; c=json.load(open('$CATALOG')); print(c['backends'].get('$BACKEND_KEY',{}).get('sizeBytes',0))")
  if [[ -n "$EXPECTED" && "$EXPECTED" -gt 0 ]]; then
    GOT=$(stat -c '%s' "$archive" 2>/dev/null || stat -f '%z' "$archive")
    MIN=$(( EXPECTED * 95 / 100 ))
    if (( GOT < MIN )); then
      ely_fail "Engine archive is $GOT bytes, expected ~$EXPECTED. Bad download."
      rm -f "$archive"
      exit 6
    fi
  fi
  ely_info "Extracting..."
  ely_extract "$archive" "$BACKEND_DIR"
  rm -f "$archive"
  chmod +x "$ENTRY" 2>/dev/null || true
  [[ -x "$ENTRY" ]] || { ely_fail "Expected entrypoint missing: $ENTRY"; exit 5; }
  ely_ok "Engine extracted"
fi

# ---------- Model menu + download (shared) ----------
ely_step 3 "Choose models to install"
ely_show_menu
echo
read -r -p "  Enter numbers comma-separated (e.g. 1,3), or A / R: " SEL
SEL="${SEL:-R}"
SELECTED_IDS=()
while IFS= read -r id; do [[ -n "$id" ]] && SELECTED_IDS+=("$id"); done < <(ely_parse_selection "$SEL")
(( ${#SELECTED_IDS[@]} == 0 )) && { ely_fail "No valid models selected"; exit 6; }
ely_ok "Selected: ${SELECTED_IDS[*]}"

ely_step 4 "Downloading model weights"
for id in "${SELECTED_IDS[@]}"; do ely_download_model "$id" || true; done

# ---------- Register + smoke test (shared) ----------
ely_step 5 "Registering models with the engine"
ely_start_engine "$ENTRY" || { ely_fail "Engine failed to start"; tail -n 20 "$BACKEND_DIR/serve.log"; exit 7; }
ely_ok "Engine online"

IMPORTED=()
for id in "${SELECTED_IDS[@]}"; do
  ely_register_model "$id" "$ENTRY" && IMPORTED+=("$id")
done

SMOKE_TPS=0
if (( ${#IMPORTED[@]} > 0 )); then
  ely_step 6 "Smoke test"
  TEST_ID="${IMPORTED[0]}"
  for id in "${IMPORTED[@]}"; do [[ "$id" == "gemma2-2b" ]] && TEST_ID="$id"; done
  SMOKE_TPS=$(ely_smoke_test "$TEST_ID")
  ely_ok "Throughput: $SMOKE_TPS tok/s"
fi

ely_stop_engine

# ---------- Persist ----------
: >"$MODELS/installed-models.txt"
for id in "${IMPORTED[@]}"; do
  ely_load_model "$id"
  echo "$id|$M_NAME|$M_QUALITY" >>"$MODELS/installed-models.txt"
done
ely_write_state "Shared/bin/$BACKEND_KEY/$BACKEND_ENTRY" "$SMOKE_TPS" "${IMPORTED[@]}"

# ---------- Optional: Node.js portable for agent dashboard ----------
TOOLS_DIR="$SHARED/tools"
NODE_DIR="$TOOLS_DIR/node"
NODE_BIN="$NODE_DIR/bin/node"
if [[ ! -x "$NODE_BIN" ]]; then
  NODE_URL=$(python3 -c "import json; c=json.load(open('$CATALOG')); print(c.get('tools',{}).get('node-linux-x64',{}).get('url',''))")
  if [[ -n "$NODE_URL" ]]; then
    ely_info "Downloading Node.js portable for the agent dashboard ..."
    mkdir -p "$NODE_DIR"
    ARC="$NODE_DIR/_node.tar.xz"
    if curl $CURL_OPTS -C - "$NODE_URL" -o "$ARC" 2>/dev/null; then
      tar -xJf "$ARC" -C "$NODE_DIR" --strip-components=1 2>/dev/null && ely_ok "Node.js portable installed"
      rm -f "$ARC"
    else
      ely_info "Node.js download failed (agent dashboard will be unavailable)"
    fi
  fi
fi

ely_banner "Install summary"
echo "  Backend:    $BACKEND_LABEL"
echo "  Models:     ${#IMPORTED[@]} of ${#SELECTED_IDS[@]}"
for id in "${IMPORTED[@]}"; do ely_load_model "$id"; echo "    - $M_NAME"; done
echo "  Throughput: $SMOKE_TPS tok/s"
echo
echo "  Done. Run Linux/start.sh to launch."
(( ${#IMPORTED[@]} == 0 )) && exit 8
exit 0
