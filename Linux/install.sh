#!/usr/bin/env bash
# Eight.ly Stick - Linux installer (wrapper). Heavy lifting in Shared/install-lib.sh.
# CPU-only for now. NVIDIA CUDA / Intel Arc (IPEX-LLM ubuntu) are planned.

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

ely_banner "Eight.ly Stick Setup (Linux)"

# ---------- Platform detection (Linux-specific) ----------
ely_step 1 "Detecting hardware"
CPU_NAME=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | sed 's/^[^:]*: //' || echo 'unknown')
BACKEND_KEY="linux-cpu"
GPU_NAME="$CPU_NAME"
export BACKEND_KEY GPU_NAME
ely_ok "CPU: $CPU_NAME"
ely_info "NOTE: Linux build is CPU-only in this release. GPU backends (CUDA, Intel Arc) coming."

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
    curl $CURL_OPTS "$BACKEND_URL" -o "$archive" && break
    (( attempt >= 3 )) && { ely_fail "Engine download failed"; exit 4; }
    ely_info "Attempt $attempt failed, retrying..."; sleep 2
  done
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

ely_banner "Install summary"
echo "  Backend:    $BACKEND_LABEL"
echo "  Models:     ${#IMPORTED[@]} of ${#SELECTED_IDS[@]}"
for id in "${IMPORTED[@]}"; do ely_load_model "$id"; echo "    - $M_NAME"; done
echo "  Throughput: $SMOKE_TPS tok/s"
echo
echo "  Done. Run Linux/start.sh to launch."
(( ${#IMPORTED[@]} == 0 )) && exit 8
exit 0
