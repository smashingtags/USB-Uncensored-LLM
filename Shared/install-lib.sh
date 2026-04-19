#!/usr/bin/env bash
# Eight.ly Stick - shared install/launch library (sourced, not executed).
# Works on both macOS (bash 3.2) and Linux (bash 4+). No associative arrays.
#
# Callers must set:
#   ROOT, SHARED, BIN, MODELS, OLLAMA_DATA, CATALOG, STATE  - filesystem paths
#   BACKEND_KEY                                              - e.g. darwin-apple
#   GPU_NAME                                                 - human-readable label
#   INSTALL_PORT                                             - numeric, default 11439
# And optionally override: ELY_COLORS (1/0), curl options in CURL_OPTS.

INSTALL_PORT="${INSTALL_PORT:-11439}"
CURL_OPTS="${CURL_OPTS:---fail --progress-bar -L}"

if [[ -t 1 && "${ELY_COLORS:-1}" == "1" ]]; then
  ELY_CY=$'\033[36m'; ELY_YE=$'\033[33m'; ELY_GN=$'\033[32m'
  ELY_RD=$'\033[31m'; ELY_DM=$'\033[2m';  ELY_O=$'\033[0m'
else
  ELY_CY=''; ELY_YE=''; ELY_GN=''; ELY_RD=''; ELY_DM=''; ELY_O=''
fi

ely_banner() {
  printf '\n%s%s%s\n' "$ELY_CY" "$(printf '=%.0s' $(seq 1 58))" "$ELY_O"
  printf '%s  %s%s\n'  "$ELY_CY" "$1" "$ELY_O"
  printf '%s%s%s\n'    "$ELY_CY" "$(printf '=%.0s' $(seq 1 58))" "$ELY_O"
}
ely_step() { printf '%s[%s]%s %s\n' "$ELY_YE" "$1" "$ELY_O" "$2"; }
ely_ok()   { printf '     %s[OK]%s %s\n' "$ELY_GN" "$ELY_O" "$1"; }
ely_fail() { printf '     %s[X]%s  %s\n' "$ELY_RD" "$ELY_O" "$1"; }
ely_info() { printf '       %s%s%s\n'    "$ELY_DM" "$1" "$ELY_O"; }

# Cross-platform file size helper (Mac: stat -f%z, Linux/GNU: stat -c%s).
ely_file_size() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

# Extract any supported archive based on extension.
ely_extract() {
  local archive="$1" dest="$2"
  case "$archive" in
    *.tgz|*.tar.gz) tar -xzf "$archive" -C "$dest" ;;
    *.zip)          /usr/bin/unzip -q -o "$archive" -d "$dest" ;;
    *) ely_fail "Unknown archive type: $archive"; return 1 ;;
  esac
}

# Catalog field lookup by dot-path. Single python call per invocation.
ely_j() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if k.isdigit(): d = d[int(k)]
    else: d = d[k]
print(d)' "$CATALOG" "$1"
}

# Load all fields of a model into shell vars in one python call.
# Produces M_ID, M_NAME, M_FILE, M_URL, M_SIZEBYTES, M_SIZELABEL, M_QUALITY,
# M_SYSTEMPROMPT, M_PARAMS_TEMPERATURE, M_PARAMS_TOP_P.
ely_load_model() {
  local id="$1"
  eval "$(python3 -c "
import json, sys, shlex
cat = json.load(open(sys.argv[1]))
m = next((x for x in cat['models'] if x['id'] == sys.argv[2]), None)
if m is None: sys.exit(2)
def emit(k, v): print(f'M_{k}={shlex.quote(str(v))}')
for k in ('id','name','file','url','sizeBytes','sizeLabel','quality','systemPrompt'):
    if k in m: emit(k.upper(), m[k])
p = m.get('params') or {}
for k,v in p.items():
    emit('PARAMS_' + k.upper().replace('-', '_'), v)
" "$CATALOG" "$id")"
}

ely_show_menu() {
  python3 -c '
import json, sys
cat = json.load(open(sys.argv[1]))
for i, m in enumerate(cat["models"], 1):
    print(f"  [{i}] {m[\"name\"]:<42} {m[\"sizeLabel\"]:<8} {m[\"badge\"]}")
print("  [A] All")
print("  [R] Recommended only (Gemma 2 2B)")' "$CATALOG"
}

# Parse menu input ("1,3", "A", "R") into a newline-separated list of model IDs.
ely_parse_selection() {
  python3 -c '
import json, sys, re
cat = json.load(open(sys.argv[1]))
sel = sys.argv[2].strip()
ms = cat["models"]
picked = []
if re.match(r"^[Aa]", sel):                              picked = ms
elif re.match(r"^[Rr]", sel) or not sel:                 picked = [m for m in ms if m["id"] == "gemma2-2b"]
else:
    for p in re.split(r"\s*,\s*", sel):
        if p.isdigit():
            i = int(p) - 1
            if 0 <= i < len(ms): picked.append(ms[i])
print("\n".join(m["id"] for m in picked))' "$CATALOG" "$1"
}

# Download a model if not already present at ~90% expected size.
ely_download_model() {
  local id="$1"
  ely_load_model "$id" || { ely_fail "Model $id not in catalog"; return 1; }
  local dest="$MODELS/$M_FILE"
  local min=$(( M_SIZEBYTES * 9 / 10 ))
  if [[ -f "$dest" ]] && (( $(ely_file_size "$dest") >= min )); then
    ely_ok "$M_NAME already downloaded"
    return 0
  fi
  ely_info "Downloading $M_NAME ($M_SIZELABEL)..."
  local attempt=0
  while (( attempt < 3 )); do
    attempt=$((attempt + 1))
    if curl $CURL_OPTS -C - "$M_URL" -o "$dest"; then
      if (( $(ely_file_size "$dest") >= min )); then
        ely_ok "$M_NAME downloaded"; return 0
      fi
    fi
    ely_info "Attempt $attempt failed, retrying..."; sleep 3
  done
  ely_fail "Download of $M_NAME failed"
  return 1
}

# Start Ollama for the install phase (foreground kill at end via $ely_engine_pid).
ely_start_engine() {
  local entry="$1"
  local url="http://127.0.0.1:$INSTALL_PORT"
  pkill -9 -f 'ollama' >/dev/null 2>&1 || true
  sleep 2
  export OLLAMA_MODELS="$OLLAMA_DATA"
  export OLLAMA_HOST="127.0.0.1:$INSTALL_PORT"
  "$entry" serve >"$SHARED/bin/$BACKEND_KEY/serve.log" 2>&1 &
  ely_engine_pid=$!
  local i
  for i in $(seq 1 15); do
    curl -s --max-time 2 "$url/api/tags" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

ely_stop_engine() {
  kill "${ely_engine_pid:-0}" 2>/dev/null || true
  sleep 1
  pkill -9 -f 'ollama' >/dev/null 2>&1 || true
}

# Write Modelfile and run `ollama create`, then verify manifest via /api/tags.
ely_register_model() {
  local id="$1" entry="$2"
  ely_load_model "$id" || return 1
  [[ -f "$MODELS/$M_FILE" ]] || { ely_info "Skip $M_NAME - file missing"; return 2; }

  local mf="$MODELS/Modelfile-$id"
  cat >"$mf" <<EOF
FROM ./$M_FILE
PARAMETER temperature $M_PARAMS_TEMPERATURE
PARAMETER top_p $M_PARAMS_TOP_P
SYSTEM "$M_SYSTEMPROMPT"
EOF
  ( cd "$MODELS" && "$entry" create "$id" -f "$mf" >/dev/null 2>&1 )
  local rc=$?
  (( rc != 0 )) && { ely_fail "$M_NAME - ollama create failed (rc=$rc)"; return 3; }

  local found
  found=$(curl -s "http://127.0.0.1:$INSTALL_PORT/api/tags" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
print(int(any(re.match(r'^${id}:', m['name']) for m in d.get('models', []))))
")
  if [[ "$found" == "1" ]]; then
    ely_ok "$M_NAME registered"
    return 0
  fi
  ely_fail "$M_NAME - created but manifest not visible"
  return 4
}

# Returns tok/s via stdout after a 100-token timed generation.
ely_smoke_test() {
  local id="$1"
  local url="http://127.0.0.1:$INSTALL_PORT"
  # Warmup
  curl -s -X POST "$url/api/generate" -H "Content-Type: application/json" \
    -d "{\"model\":\"$id\",\"prompt\":\"Hi\",\"stream\":false,\"options\":{\"num_predict\":8}}" \
    --max-time 180 >/dev/null 2>&1 || true
  # Timed
  local resp
  resp=$(curl -s -X POST "$url/api/generate" -H "Content-Type: application/json" \
    -d "{\"model\":\"$id\",\"prompt\":\"Write 100 words about the future of portable AI.\",\"stream\":false,\"options\":{\"num_predict\":100,\"temperature\":0.7}}" \
    --max-time 180)
  echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ms = round(d.get('eval_duration', 0) / 1_000_000)
    n = d.get('eval_count', 0)
    print(round(n * 1000.0 / ms, 2) if ms > 0 else 0)
except Exception:
    print(0)
"
}

# Persist install-state.json.
ely_write_state() {
  local backend_entry="$1" tps="$2"; shift 2
  local ids=("$@")
  python3 - "$CATALOG" "$BACKEND_KEY" "$(ely_j "backends.$BACKEND_KEY.label")" "$GPU_NAME" "$backend_entry" "$tps" "$STATE" "${ids[@]}" <<'PY'
import json, sys, datetime
args = sys.argv[1:]
catalog, backend, label, gpu, entry, tps, state_path = args[:7]
ids = args[7:]
cat = json.load(open(catalog))
installed = [
    {'id': m['id'], 'name': m['name'], 'file': m['file'],
     'engine': backend}
    for m in cat['models'] if m['id'] in ids
]
state = {
    'product': cat['product'],
    'version': cat['version'],
    'backend': backend,
    'backendLabel': label,
    'gpu': gpu,
    'entrypoint': entry,
    'installedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'smokeTokensPerSec': float(tps),
    'secondaryBackends': [],
    'installed': installed,
}
open(state_path, 'w').write(json.dumps(state, indent=2))
PY
}
