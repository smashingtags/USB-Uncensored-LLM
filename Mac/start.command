#!/usr/bin/env bash
# Eight.ly Forge - macOS launcher
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(cd .. && pwd)"
SHARED="$ROOT/Shared"
STATE="$SHARED/install-state.json"
CATALOG="$SHARED/catalog.json"

echo
echo "  ========================================================"
echo "                     EIGHT.LY FORGE"
echo "  ========================================================"
echo

if [[ ! -f "$STATE" ]]; then
  echo "  No install detected."
  echo "  Run Mac/install.command first to pick your models."
  read -r -p "  Press Enter to close..." _
  exit 1
fi

BACKEND=$(python3 -c "import json; print(json.load(open('$STATE'))['backend'])")
ENTRY_REL=$(python3 -c "import json; print(json.load(open('$STATE'))['entrypoint'])")
BACKEND_LABEL=$(python3 -c "import json; print(json.load(open('$STATE'))['backendLabel'])")
GPU=$(python3 -c "import json; print(json.load(open('$STATE'))['gpu'])")
ENTRY="$ROOT/$ENTRY_REL"
BACKEND_DIR="$SHARED/bin/$BACKEND"

echo "  GPU:     $GPU"
echo "  Backend: $BACKEND_LABEL"
echo

if [[ ! -x "$ENTRY" ]]; then
  echo "  ERROR: engine missing at $ENTRY"
  echo "  Re-run Mac/install.command to repair."
  read -r -p "  Press Enter to close..." _
  exit 2
fi

# Backend env from catalog
eval "$(python3 -c "
import json
cat = json.load(open('$CATALOG'))
for k,v in cat['backends']['$BACKEND']['env'].items():
    print(f'export {k}={v!r}')
")"

export OLLAMA_MODELS="$SHARED/models/ollama_data"
export OLLAMA_HOST="127.0.0.1:11438"
export OLLAMA_ORIGINS="*"
export ELY_OLLAMA_URL="http://127.0.0.1:11438"
export ELY_CHAT_PORT="3333"

if curl -s --max-time 2 http://127.0.0.1:11438/api/tags >/dev/null 2>&1; then
  echo "  [OK] Engine already running on :11438."
else
  echo "  Starting engine on :11438..."
  ( cd "$BACKEND_DIR" && "$ENTRY" serve >"$BACKEND_DIR/serve.log" 2>&1 ) &
  ENGINE_PID=$!
  for _ in {1..30}; do
    if curl -s --max-time 2 http://127.0.0.1:11438/api/tags >/dev/null 2>&1; then break; fi
    sleep 1
  done
  if ! curl -s --max-time 2 http://127.0.0.1:11438/api/tags >/dev/null 2>&1; then
    echo "  ERROR: engine did not come up within 30s."
    [[ -f "$BACKEND_DIR/serve.log" ]] && tail -n 20 "$BACKEND_DIR/serve.log"
    read -r -p "  Press Enter to close..." _
    exit 3
  fi
  echo "  [OK] Engine online."
fi

cleanup(){
  echo
  echo "  Shutting down engines..."
  pkill -9 -f 'ollama' 2>/dev/null || true
  pkill -9 -f 'llama-server' 2>/dev/null || true
  pkill -9 -f 'Shared/agent/server.mjs' 2>/dev/null || true
  echo "  Done."
}
trap cleanup EXIT INT TERM

# Optional: agent dashboard on :3334 (Node.js portable).
ELY_AGENT_PORT="${ELY_AGENT_PORT:-3334}"
NODE_BIN=""
[[ -x "$SHARED/tools/node/bin/node" ]] && NODE_BIN="$SHARED/tools/node/bin/node"
if [[ -n "$NODE_BIN" && -f "$SHARED/agent/server.mjs" ]]; then
  echo "  Starting agent dashboard on :$ELY_AGENT_PORT..."
  ELY_AGENT_PORT="$ELY_AGENT_PORT" "$NODE_BIN" "$SHARED/agent/server.mjs" >"$SHARED/chat_data/agent.log" 2>&1 &
fi

# chat_server.py prints the one authoritative banner. Don't duplicate here.
( sleep 1 && /usr/bin/open http://localhost:3333 ) >/dev/null 2>&1 &
exec python3 "$SHARED/chat_server.py"
