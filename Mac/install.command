#!/usr/bin/env bash
# Eight.ly Forge - macOS installer (wrapper). Platform-specific pieces here;
# heavy lifting lives in Shared/install-lib.sh.

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

command -v python3 >/dev/null 2>&1 || { echo "python3 not found. macOS 12.3+ ships Python 3. Run 'xcode-select --install' if missing." >&2; exit 1; }
[[ -f "$CATALOG" ]] || { echo "Missing $CATALOG" >&2; exit 2; }
# shellcheck disable=SC1090
source "$SHARED/install-lib.sh"

ely_banner "Eight.ly Forge Setup (macOS)"

# ---------- Platform detection (Mac-specific) ----------
ely_step 1 "Detecting hardware"
ARCH="$(uname -m)"
BACKEND_KEY="darwin-apple"
if [[ "$ARCH" == "arm64" ]]; then
  GPU_NAME="Apple Silicon ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown))"
else
  GPU_NAME="Intel Mac ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown))"
fi
export BACKEND_KEY GPU_NAME
ely_ok "Arch: $ARCH"
ely_info "GPU: $GPU_NAME"

BACKEND_LABEL=$(ely_j "backends.$BACKEND_KEY.label")
BACKEND_URL=$(  ely_j "backends.$BACKEND_KEY.url")
BACKEND_ENTRY=$(ely_j "backends.$BACKEND_KEY.entrypoint")
ely_info "Backend: $BACKEND_LABEL"

BACKEND_DIR="$BIN/$BACKEND_KEY"
ENTRY="$BACKEND_DIR/$BACKEND_ENTRY"

# ---------- Engine install (zip on macOS) ----------
ely_step 2 "Installing engine"
if [[ -x "$ENTRY" ]]; then
  ely_ok "Engine already present"
else
  mkdir -p "$BACKEND_DIR"
  archive="$BACKEND_DIR/_download.zip"
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
  # Ollama.app ships the binary nested; symlink up to the configured path
  if [[ ! -x "$ENTRY" ]]; then
    found=$(find "$BACKEND_DIR" -type f -name ollama 2>/dev/null | head -1)
    [[ -n "$found" ]] && { ln -sf "$found" "$ENTRY" 2>/dev/null || cp "$found" "$ENTRY"; chmod +x "$ENTRY"; }
  fi
  [[ -x "$ENTRY" ]] || { ely_fail "Expected entrypoint missing: $ENTRY"; exit 5; }
  xattr -dr com.apple.quarantine "$BACKEND_DIR" 2>/dev/null || true
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
[[ ${#SELECTED_IDS[@]} -eq 0 ]] && { ely_fail "No valid models selected"; exit 6; }
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
  ely_step 6 "Smoke test (proves acceleration)"
  TEST_ID="${IMPORTED[0]}"
  for id in "${IMPORTED[@]}"; do [[ "$id" == "gemma2-2b" ]] && TEST_ID="$id"; done
  ely_info "Warming up $TEST_ID..."
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
  ARCH=$(uname -m)
  NODE_KEY="node-darwin-x64"
  [[ "$ARCH" == "arm64" ]] && NODE_KEY="node-darwin-arm64"
  NODE_URL=$(python3 -c "import json; c=json.load(open('$CATALOG')); print(c.get('tools',{}).get('$NODE_KEY',{}).get('url',''))")
  if [[ -n "$NODE_URL" ]]; then
    ely_info "Downloading Node.js portable for the agent dashboard ..."
    mkdir -p "$NODE_DIR"
    ARC="$NODE_DIR/_node.tar.gz"
    if curl $CURL_OPTS -C - "$NODE_URL" -o "$ARC" 2>/dev/null; then
      tar -xzf "$ARC" -C "$NODE_DIR" --strip-components=1 2>/dev/null && ely_ok "Node.js portable installed"
      rm -f "$ARC"
    else
      ely_info "Node.js download failed (agent dashboard will be unavailable)"
    fi
  fi
fi

ely_banner "Install summary"
echo "  Backend:    $BACKEND_LABEL"
echo "  GPU:        $GPU_NAME"
echo "  Models:     ${#IMPORTED[@]} of ${#SELECTED_IDS[@]} selected"
for id in "${IMPORTED[@]}"; do ely_load_model "$id"; echo "    - $M_NAME"; done
echo "  Throughput: $SMOKE_TPS tok/s"
echo
echo "  Done. Double-click Mac/start.command to launch."
(( ${#IMPORTED[@]} == 0 )) && exit 8
exit 0
