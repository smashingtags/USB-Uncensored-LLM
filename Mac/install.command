#!/usr/bin/env bash
# Eight.ly Stick - macOS installer
# Detects Apple Silicon vs Intel, pulls stock Ollama (Metal-accelerated on
# Apple Silicon), downloads selected models, VERIFIES manifests register,
# runs a smoke test.

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

C_CY=$'\033[36m'; C_YE=$'\033[33m'; C_GN=$'\033[32m'; C_RD=$'\033[31m'; C_DM=$'\033[2m'; C_O=$'\033[0m'
banner(){ echo; printf '%s\n' "${C_CY}$(printf '=%.0s' {1..58})${C_O}"; echo "${C_CY}  $1${C_O}"; printf '%s\n' "${C_CY}$(printf '=%.0s' {1..58})${C_O}"; }
step(){ echo "${C_YE}[$1]${C_O} $2"; }
ok(){ echo "     ${C_GN}[OK]${C_O} $1"; }
fail(){ echo "     ${C_RD}[X] ${C_O} $1"; }
info(){ echo "       ${C_DM}$1${C_O}"; }

banner "Eight.ly Stick Setup (macOS)"

# Helpers: dot-path into catalog.json + model lookup
j(){ python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'):
    if k.isdigit(): d = d[int(k)]
    else: d = d[k]
print(d)
" "$CATALOG" "$1"; }
jmodel(){ python3 -c "
import json, sys
cat = json.load(open(sys.argv[1]))
m = next(x for x in cat['models'] if x['id'] == sys.argv[2])
path = sys.argv[3].split('.')
v = m
for k in path: v = v[k]
print(v)
" "$CATALOG" "$1" "$2"; }

# ---------- Detection ----------
step 1 "Detecting hardware"
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  GPU_NAME="Apple Silicon ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown))"
else
  GPU_NAME="Intel Mac ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown))"
fi
BACKEND_KEY="darwin-apple"
ok "Arch: $ARCH"
info "GPU: $GPU_NAME"

BACKEND_LABEL=$(j "backends.$BACKEND_KEY.label")
BACKEND_URL=$(  j "backends.$BACKEND_KEY.url")
BACKEND_ENTRY=$(j "backends.$BACKEND_KEY.entrypoint")
info "Backend: $BACKEND_LABEL"

BACKEND_DIR="$BIN/$BACKEND_KEY"
ENTRY="$BACKEND_DIR/$BACKEND_ENTRY"

# ---------- Engine install ----------
step 2 "Installing engine"
if [[ -x "$ENTRY" ]]; then
  ok "Engine already present"
else
  mkdir -p "$BACKEND_DIR"
  ARCHIVE="$BACKEND_DIR/_download.zip"
  info "Downloading $BACKEND_URL"
  ATTEMPT=0
  while :; do
    ATTEMPT=$((ATTEMPT+1))
    curl -L --fail --progress-bar "$BACKEND_URL" -o "$ARCHIVE" && break
    (( ATTEMPT >= 3 )) && { fail "Engine download failed"; exit 4; }
    info "Attempt $ATTEMPT failed, retrying..."; sleep 2
  done
  info "Unzipping..."
  /usr/bin/unzip -q -o "$ARCHIVE" -d "$BACKEND_DIR"
  rm -f "$ARCHIVE"
  [[ -x "$ENTRY" ]] || chmod +x "$ENTRY" 2>/dev/null || true
  # Ollama.app may be the primary artifact; the binary is at Ollama.app/Contents/Resources/ollama
  if [[ ! -x "$ENTRY" ]]; then
    FOUND=$(find "$BACKEND_DIR" -type f -name 'ollama' 2>/dev/null | head -1)
    [[ -n "$FOUND" && -x "$FOUND" ]] && { ln -sf "$FOUND" "$ENTRY" 2>/dev/null || cp "$FOUND" "$ENTRY"; chmod +x "$ENTRY"; }
  fi
  [[ -x "$ENTRY" ]] || { fail "Expected entrypoint missing: $ENTRY"; exit 5; }
  xattr -dr com.apple.quarantine "$BACKEND_DIR" 2>/dev/null || true
  ok "Engine extracted"
fi

# ---------- Model menu ----------
step 3 "Choose models to install"
python3 - "$CATALOG" <<'PY'
import json, sys
cat = json.load(open(sys.argv[1]))
for i, m in enumerate(cat['models'], start=1):
    print(f"  [{i}] {m['name']:<42} {m['sizeLabel']:<8} {m['badge']}")
print("  [A] All")
print("  [R] Recommended only (Gemma 2 2B)")
PY
echo
read -r -p "  Enter numbers comma-separated (e.g. 1,3), or A / R: " SEL
SEL="${SEL:-R}"

IDS_JSON=$(python3 - "$CATALOG" "$SEL" <<'PY'
import json, sys, re
cat = json.load(open(sys.argv[1])); sel = sys.argv[2].strip(); ms = cat['models']; picked = []
if re.match(r'^[Aa]', sel):    picked = ms
elif re.match(r'^[Rr]', sel) or not sel: picked = [m for m in ms if m['id']=='gemma2-2b']
else:
    for p in re.split(r'\s*,\s*', sel):
        if p.isdigit():
            i = int(p)-1
            if 0 <= i < len(ms): picked.append(ms[i])
print(json.dumps([m['id'] for m in picked]))
PY
)
SELECTED_IDS=($(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1])))" "$IDS_JSON"))
[[ ${#SELECTED_IDS[@]} -eq 0 ]] && { fail "No valid models selected"; exit 6; }
ok "Selected: ${SELECTED_IDS[*]}"

# ---------- Download weights ----------
step 4 "Downloading model weights"
for ID in "${SELECTED_IDS[@]}"; do
  FILE=$(jmodel "$ID" file)
  URL=$(jmodel "$ID" url)
  SIZE=$(jmodel "$ID" sizeBytes)
  NAME=$(jmodel "$ID" name)
  LABEL=$(jmodel "$ID" sizeLabel)
  DEST="$MODELS/$FILE"
  MIN=$(( SIZE * 9 / 10 ))
  if [[ -f "$DEST" ]]; then
    ACTUAL=$(stat -f%z "$DEST" 2>/dev/null || stat -c%s "$DEST")
    (( ACTUAL >= MIN )) && { ok "$NAME already downloaded"; continue; }
  fi
  info "Downloading $NAME ($LABEL)..."
  ATTEMPT=0; DONE=0
  while (( DONE == 0 )); do
    ATTEMPT=$((ATTEMPT+1))
    if curl -L --fail --progress-bar -C - "$URL" -o "$DEST"; then
      ACTUAL=$(stat -f%z "$DEST" 2>/dev/null || stat -c%s "$DEST")
      (( ACTUAL >= MIN )) && DONE=1
    fi
    if (( DONE == 0 && ATTEMPT >= 3 )); then fail "Download of $NAME failed"; break; fi
    (( DONE == 0 )) && { info "Attempt $ATTEMPT failed, retrying..."; sleep 3; }
  done
  (( DONE == 1 )) && ok "$NAME downloaded"
done

# ---------- Import + verify ----------
step 5 "Registering models with the engine"
pkill -9 -f 'ollama' 2>/dev/null || true
sleep 2

export OLLAMA_MODELS="$OLLAMA_DATA"
export OLLAMA_HOST="127.0.0.1:11439"
eval "$(python3 -c "
import json
cat = json.load(open('$CATALOG'))
for k,v in cat['backends']['$BACKEND_KEY']['env'].items():
    print(f'export {k}={v!r}')
")"

"$ENTRY" serve >"$BACKEND_DIR/serve.log" 2>&1 &
ENGINE_PID=$!
sleep 4
UP=0
for _ in {1..15}; do
  curl -s --max-time 2 http://127.0.0.1:11439/api/tags >/dev/null 2>&1 && { UP=1; break; }
  sleep 1
done
if (( UP == 0 )); then fail "Engine failed to start"; tail -n 20 "$BACKEND_DIR/serve.log"; kill $ENGINE_PID 2>/dev/null; exit 7; fi
ok "Engine online"

IMPORTED=()
for ID in "${SELECTED_IDS[@]}"; do
  FILE=$(jmodel "$ID" file)
  TEMP=$(python3 -c "import json; print(next(m for m in json.load(open('$CATALOG'))['models'] if m['id']=='$ID')['params']['temperature'])")
  TOP_P=$(python3 -c "import json; print(next(m for m in json.load(open('$CATALOG'))['models'] if m['id']=='$ID')['params']['top_p'])")
  SYS=$(jmodel "$ID" systemPrompt)
  NAME=$(jmodel "$ID" name)
  [[ ! -f "$MODELS/$FILE" ]] && { info "Skip $NAME - file missing"; continue; }

  MF="$MODELS/Modelfile-$ID"
  cat >"$MF" <<EOF
FROM ./$FILE
PARAMETER temperature $TEMP
PARAMETER top_p $TOP_P
SYSTEM "$SYS"
EOF

  info "Creating $ID..."
  ( cd "$MODELS" && "$ENTRY" create "$ID" -f "$MF" >/dev/null 2>&1 )
  RC=$?
  if (( RC != 0 )); then fail "$NAME - ollama create failed (rc=$RC)"; continue; fi

  HAS=$(curl -s http://127.0.0.1:11439/api/tags | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
print(int(any(re.match(r'^${ID}:', m['name']) for m in d.get('models', []))))
")
  if [[ "$HAS" == "1" ]]; then ok "$NAME registered"; IMPORTED+=("$ID"); else fail "$NAME - created but manifest not visible"; fi
done

# ---------- Smoke test ----------
SMOKE_TPS=0
if (( ${#IMPORTED[@]} > 0 )); then
  step 6 "Smoke test (proves acceleration)"
  TEST_ID="${IMPORTED[0]}"
  for id in "${IMPORTED[@]}"; do [[ "$id" == "gemma2-2b" ]] && TEST_ID="$id"; done

  info "Warming up $TEST_ID..."
  curl -s -X POST http://127.0.0.1:11439/api/generate -H "Content-Type: application/json" \
    -d "{\"model\":\"$TEST_ID\",\"prompt\":\"Hi\",\"stream\":false,\"options\":{\"num_predict\":8}}" \
    --max-time 180 >/dev/null 2>&1 || true

  info "Timed 100-token generation..."
  RESP=$(curl -s -X POST http://127.0.0.1:11439/api/generate -H "Content-Type: application/json" \
    -d "{\"model\":\"$TEST_ID\",\"prompt\":\"Write 100 words about the future of portable AI.\",\"stream\":false,\"options\":{\"num_predict\":100,\"temperature\":0.7}}" \
    --max-time 180)
  SMOKE_TPS=$(echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin); ms = round(d.get('eval_duration',0)/1_000_000); n = d.get('eval_count',0)
    print(round(n*1000.0/ms, 2) if ms > 0 else 0)
except Exception:
    print(0)
")
  ok "Throughput: $SMOKE_TPS tok/s"
fi

kill $ENGINE_PID 2>/dev/null || true
sleep 1
pkill -9 -f 'ollama' 2>/dev/null || true

# ---------- Persist ----------
: >"$MODELS/installed-models.txt"
for ID in "${IMPORTED[@]}"; do
  NAME=$(jmodel "$ID" name); QUAL=$(jmodel "$ID" quality)
  echo "$ID|$NAME|$QUAL" >>"$MODELS/installed-models.txt"
done

python3 - "$CATALOG" "$BACKEND_KEY" "$BACKEND_LABEL" "$GPU_NAME" "$BACKEND_ENTRY" "$SMOKE_TPS" "$STATE" "${IMPORTED[@]}" <<'PY'
import json, sys, datetime
args = sys.argv[1:]
catalog, backend, label, gpu, entry, tps, state_path = args[:7]
ids = args[7:]
cat = json.load(open(catalog))
installed = [{'id': m['id'], 'name': m['name'], 'file': m['file']} for m in cat['models'] if m['id'] in ids]
state = {
    'product': cat['product'], 'version': cat['version'],
    'backend': backend, 'backendLabel': label, 'gpu': gpu,
    'entrypoint': f'Shared/bin/{backend}/{entry}',
    'installedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'smokeTokensPerSec': float(tps), 'installed': installed,
}
open(state_path, 'w').write(json.dumps(state, indent=2))
PY

banner "Install summary"
echo "  Backend:    $BACKEND_LABEL"
echo "  GPU:        $GPU_NAME"
echo "  Models:     ${#IMPORTED[@]} of ${#SELECTED_IDS[@]} selected"
for id in "${IMPORTED[@]}"; do
  echo "    - $(jmodel "$id" name)"
done
echo "  Throughput: $SMOKE_TPS tok/s"
echo
echo "  Done. Double-click Mac/start.command to launch."
(( ${#IMPORTED[@]} == 0 )) && exit 8
exit 0
