#!/bin/bash
# =================================================================
#  Portable AI USB - Start AI (macOS)
# =================================================================

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[90m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
DATA_DIR="$ROOT_DIR/data"
ENV_FILE="$DATA_DIR/ai_settings.env"

# Detect Node.js
NODE_DIR=""
for d in "$BIN_DIR"/node-v*-darwin-*/; do
    [ -f "$d/bin/node" ] && NODE_DIR="$d" && break
done
if [ -z "$NODE_DIR" ]; then
    echo -e "  ${RED}[ERROR] Node.js not found! Run setup_first_time.sh first.${RESET}"
    exit 1
fi
export PATH="$NODE_DIR/bin:$PATH"

# Portable data
export CLAUDE_CONFIG_DIR="$DATA_DIR/openclaude"
export XDG_CONFIG_HOME="$DATA_DIR/config"
export XDG_DATA_HOME="$DATA_DIR/app_data"
mkdir -p "$CLAUDE_CONFIG_DIR" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$DATA_DIR"

# Banner
echo ""
echo -e "${CYAN}    ____            __        __    __        ___    ____${RESET}"
echo -e "${CYAN}   / __ \\____  ____/ /_____ _/ /_  / /__     /   |  /  _/${RESET}"
echo -e "${CYAN}  / /_/ / __ \\/ __/ __/ __ \`/ __ \\/ / _ \\   / /| |  / /  ${RESET}"
echo -e "${CYAN} / ____/ /_/ / / / /_/ /_/ / /_/ / /  __/  / ___ |_/ /   ${RESET}"
echo -e "${CYAN}/_/    \\____/_/  \\__/\\__,_/_.___/_/\\___/  /_/  |_/___/   ${RESET}"
echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}Claude Code - Open Source Multi-Platform${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""

# ─── Check for flags ────────────────────────────────────────
SKIP_UPDATE=0
QUICK_MODE=0
for arg in "$@"; do
    [ "$arg" = "--offline" ] && SKIP_UPDATE=1
    [ "$arg" = "--quick" ] && QUICK_MODE=1
done

# ─── Check for Engine Updates ────────────────────────────────
if [ $SKIP_UPDATE -eq 1 ]; then
    echo -e "  ${DIM}[~] Offline mode - skipping update check${RESET}"
else
    echo -e "  ${YELLOW}[~] Checking for engine updates...${RESET}"
    cd "$BIN_DIR"
    if npm outdated @gitlawb/openclaude 2>/dev/null | grep -q openclaude; then
        echo -e "  ${YELLOW}[~] New version detected! Upgrading...${RESET}"
        npm install @gitlawb/openclaude@latest --no-audit --no-fund --loglevel=error >/dev/null 2>&1
        echo -e "  ${GREEN}[OK] Engine upgraded to latest version!${RESET}"
    else
        echo -e "  ${GREEN}[OK] Engine is up to date!${RESET}"
    fi
fi
echo ""

# ─── Check for settings ─────────────────────────────────────
goto_loaded=0
if [ -f "$ENV_FILE" ]; then
    ENV_CONTENT="$(cat "$ENV_FILE" 2>/dev/null || true)"
    if [[ "$ENV_CONTENT" == *"AI_PROVIDER="* ]]; then
        # Load settings
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^#.* ]] && continue
            [ -z "$key" ] && continue
            export "$key=$value"
        done <<< "$ENV_CONTENT"
        goto_loaded=1
    fi
fi

# ─── Provider Setup ────────────────────────────────────────
save_env() {
    echo "$1" > "$ENV_FILE"
}

setup_provider() {
    echo -e "${CYAN}=========================================================${RESET}"
    echo -e "  ${BOLD}AI PROVIDER SELECTION${RESET}"
    echo -e "${CYAN}=========================================================${RESET}"
    echo ""
    echo -e "  ${CYAN}1)${RESET} ${BOLD}OpenRouter${RESET}   ${DIM}- 200+ Free and Paid Models (Recommended)${RESET}"
    echo -e "  ${CYAN}2)${RESET} ${BOLD}Gemini${RESET}       ${DIM}- Google AI API${RESET}"
    echo -e "  ${CYAN}3)${RESET} ${BOLD}Claude${RESET}       ${DIM}- Anthropic API${RESET}"
    echo -e "  ${CYAN}4)${RESET} ${BOLD}Ollama${RESET}       ${DIM}- Local Offline AI${RESET}"
    echo -e "  ${CYAN}5)${RESET} ${BOLD}OpenAI${RESET}       ${DIM}- GPT / Codex API${RESET}"
    echo -e "  ${CYAN}6)${RESET} ${BOLD}NVIDIA NIM${RESET}   ${DIM}- Optimized GPU Inference (Free Tier)${RESET}"
    echo ""

    while true; do
        read -p "  Select your provider (1-6): " PROVIDER_SEL
        case "$PROVIDER_SEL" in
            1) setup_openrouter; return ;;
            2) setup_gemini; return ;;
            3) setup_claude; return ;;
            4) setup_ollama; return ;;
            5) setup_openai; return ;;
            6) setup_nvidia; return ;;
            *) echo -e "  ${RED}[ERROR] Invalid selection. Please choose 1-6.${RESET}" ;;
        esac
    done
}

verify_key() {
    local provider="$1" key="$2"
    echo -e "  ${YELLOW}[~] Verifying API Key... Please wait...${RESET}"
    case "$provider" in
        openrouter) curl -sf -H "Authorization: Bearer $key" https://openrouter.ai/api/v1/auth/key > /dev/null 2>&1 ;;
        gemini)     curl -sf "https://generativelanguage.googleapis.com/v1beta/models?key=$key" > /dev/null 2>&1 ;;
        anthropic)  curl -sf -H "x-api-key: $key" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models > /dev/null 2>&1 ;;
        nvidia)     curl -sf -H "Authorization: Bearer $key" https://integrate.api.nvidia.com/v1/models > /dev/null 2>&1 ;;
        openai)     curl -sf -H "Authorization: Bearer $key" https://api.openai.com/v1/models > /dev/null 2>&1 ;;
    esac
}

mask_key() {
    local key="$1"
    echo "${key:0:6}****${key: -4}"
}

setup_openrouter() {
    echo ""
    echo -e "  ${CYAN}--- OPENROUTER SETUP ---${RESET}"
    echo ""
    read -p "  Enter your OpenRouter API Key: " USER_API_KEY
    [ -z "$USER_API_KEY" ] && echo -e "  ${RED}[ERROR] Key cannot be empty!${RESET}" && setup_openrouter && return
    echo -e "  ${DIM}Key: $(mask_key "$USER_API_KEY")${RESET}"
    echo ""
    if ! verify_key openrouter "$USER_API_KEY"; then
        echo -e "  ${RED}[ERROR] Invalid or expired OpenRouter API Key!${RESET}"
        setup_openrouter; return
    fi
    echo -e "  ${GREEN}[OK] Key Verified!${RESET}"
    echo ""

    # Model selection
    echo -e "  ${CYAN}1)${RESET} Free Models"
    echo -e "  ${CYAN}2)${RESET} Paid Models"
    read -p "  Select category (1 or 2): " MODEL_TIER
    echo ""

    if [ "$MODEL_TIER" = "1" ]; then
        echo -e "  ${CYAN}--- FREE MODELS ---${RESET} ${DIM}(Fetching...)${RESET}"
        MODELS=$(curl -sf https://openrouter.ai/api/v1/models 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*:free"' | sed -e 's/"id"[[:space:]]*:[[:space:]]*"//g' -e 's/"//g' | head -20)
    else
        echo -e "  ${CYAN}--- PAID MODELS ---${RESET} ${DIM}(Fetching...)${RESET}"
        MODELS=$(curl -sf https://openrouter.ai/api/v1/models 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -e 's/"id"[[:space:]]*:[[:space:]]*"//g' -e 's/"//g' | grep -v ':free$' | head -20)
    fi

    if [ -z "$MODELS" ]; then
        echo -e "  ${YELLOW}[API Error] Could not fetch models. Enter manually.${RESET}"
        read -p "  Enter model string: " USER_MODEL
    else
        idx=1
        while IFS= read -r model; do
            echo -e "  ${CYAN}${idx})${RESET} $model"
            eval "MODEL_${idx}='$model'"
            idx=$((idx+1))
        done <<< "$MODELS"
        echo -e "  ${CYAN}${idx})${RESET} ${DIM}Custom Model...${RESET}"
        echo ""
        read -p "  Choose a model (1-$idx): " MODEL_SEL
        if [ "$MODEL_SEL" = "$idx" ]; then
            read -p "  Enter custom model string: " USER_MODEL
        else
            eval "USER_MODEL=\$MODEL_${MODEL_SEL}"
        fi
    fi

    save_env "# ========================================================
# Portable AI - Master Switchboard
# ========================================================
AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=${USER_API_KEY}
OPENAI_BASE_URL=https://openrouter.ai/api/v1
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_gemini() {
    echo ""
    echo -e "  ${CYAN}--- GEMINI SETUP ---${RESET}"
    echo ""
    read -p "  Enter your Gemini API Key: " USER_API_KEY
    [ -z "$USER_API_KEY" ] && echo -e "  ${RED}[ERROR] Key cannot be empty!${RESET}" && setup_gemini && return
    echo -e "  ${DIM}Key: $(mask_key "$USER_API_KEY")${RESET}"
    echo ""
    if ! verify_key gemini "$USER_API_KEY"; then
        echo -e "  ${RED}[ERROR] Invalid or expired Gemini API Key!${RESET}"
        setup_gemini; return
    fi
    echo -e "  ${GREEN}[OK] Key Verified!${RESET}"
    echo ""
    read -p "  Enter Model (Enter for gemini-2.0-pro-exp-02-05): " USER_MODEL
    [ -z "$USER_MODEL" ] && USER_MODEL="gemini-2.0-pro-exp-02-05"
    save_env "AI_PROVIDER=gemini
GEMINI_API_KEY=${USER_API_KEY}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_claude() {
    echo ""
    echo -e "  ${CYAN}--- CLAUDE SETUP ---${RESET}"
    echo ""
    read -p "  Enter your Anthropic API Key: " USER_API_KEY
    [ -z "$USER_API_KEY" ] && echo -e "  ${RED}[ERROR] Key cannot be empty!${RESET}" && setup_claude && return
    echo -e "  ${DIM}Key: $(mask_key "$USER_API_KEY")${RESET}"
    echo ""
    if ! verify_key anthropic "$USER_API_KEY"; then
        echo -e "  ${RED}[ERROR] Invalid or expired Anthropic API Key!${RESET}"
        setup_claude; return
    fi
    echo -e "  ${GREEN}[OK] Key Verified!${RESET}"
    echo ""
    read -p "  Enter Model (Enter for claude-3-7-sonnet-20250219): " USER_MODEL
    [ -z "$USER_MODEL" ] && USER_MODEL="claude-3-7-sonnet-20250219"
    save_env "AI_PROVIDER=anthropic
ANTHROPIC_API_KEY=${USER_API_KEY}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_ollama() {
    echo ""
    echo -e "  ${CYAN}--- OLLAMA LOCAL SETUP ---${RESET}"
    echo ""
    OLLAMA_PORT=11434
    SHARED_DIR="$ROOT_DIR/Shared"
    LOCAL_STATE="$SHARED_DIR/install-state.json"
    if [ -f "$LOCAL_STATE" ]; then
        OLLAMA_PORT=11438
        echo -e "  ${GREEN}[INFO] Using GPU-accelerated local engine on :11438${RESET}"
        echo ""
        echo -e "  ${BOLD}Installed local models:${RESET}"
        python3 -c "import json; [print('    - '+m['name']+' ('+m['id']+')') for m in json.load(open('$LOCAL_STATE')).get('installed',[])]" 2>/dev/null
        echo ""
    fi
    read -p "  Enter local model (Enter for gemma2-2b): " USER_MODEL
    [ -z "$USER_MODEL" ] && USER_MODEL="gemma2-2b"
    save_env "AI_PROVIDER=ollama
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=ollama
OPENAI_BASE_URL=http://localhost:${OLLAMA_PORT}/v1
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_openai() {
    echo ""
    echo -e "  ${CYAN}--- OPENAI / CODEX SETUP ---${RESET}"
    echo ""
    read -p "  Enter your OpenAI API Key: " USER_API_KEY
    [ -z "$USER_API_KEY" ] && echo -e "  ${RED}[ERROR] Key cannot be empty!${RESET}" && setup_openai && return
    echo -e "  ${DIM}Key: $(mask_key "$USER_API_KEY")${RESET}"
    echo ""
    if ! verify_key openai "$USER_API_KEY"; then
        echo -e "  ${RED}[ERROR] Invalid or expired OpenAI API Key!${RESET}"
        setup_openai; return
    fi
    echo -e "  ${GREEN}[OK] Key Verified!${RESET}"
    echo ""
    read -p "  Enter Model (Enter for gpt-4o): " USER_MODEL
    [ -z "$USER_MODEL" ] && USER_MODEL="gpt-4o"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=${USER_API_KEY}
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_nvidia() {
    echo ""
    echo -e "  ${CYAN}--- NVIDIA NIM SETUP ---${RESET}"
    echo ""
    read -p "  Enter your NVIDIA API Key: " USER_API_KEY
    [ -z "$USER_API_KEY" ] && echo -e "  ${RED}[ERROR] Key cannot be empty!${RESET}" && setup_nvidia && return
    echo -e "  ${DIM}Key: $(mask_key "$USER_API_KEY")${RESET}"
    echo ""
    if ! verify_key nvidia "$USER_API_KEY"; then
        echo -e "  ${RED}[ERROR] Invalid or expired NVIDIA API Key!${RESET}"
        setup_nvidia; return
    fi
    echo -e "  ${GREEN}[OK] Key Verified!${RESET}"
    echo ""

    CURATED="moonshotai/kimi-k2-instruct moonshotai/kimi-k2-thinking z-ai/glm4.7 deepseek-ai/deepseek-v3.2 deepseek-ai/deepseek-v3.1-terminus stepfun-ai/step-3.5-flash mistralai/mistral-large-3-675b-instruct-2512 qwen/qwen3-coder-480b-a35b-instruct mistralai/mistral-nemotron bytedance/seed-oss-36b-instruct mistralai/mamba-codestral-7b-v0.1 google/gemma-7b tiiuae/falcon3-7b-instruct minimaxai/minimax-m2.7"
    echo -e "  ${CYAN}--- NVIDIA MODELS ---${RESET} ${DIM}(Fetching...)${RESET}"
    LIVE=$(curl -sf -H "Authorization: Bearer $USER_API_KEY" https://integrate.api.nvidia.com/v1/models 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -e 's/"id"[[:space:]]*:[[:space:]]*"//g' -e 's/"//g' | head -15)
    MODELS=""
    for m in $CURATED; do MODELS="${MODELS}${m}"$'\n'; done
    MODELS="${MODELS}${LIVE}"

    if [ -z "$MODELS" ]; then
        echo -e "  ${YELLOW}[API Error] Could not fetch models. Entering fallback...${RESET}"
        USER_MODEL="meta/llama-3.1-70b-instruct"
    else
        idx=1
        while IFS= read -r model; do
            echo -e "  ${CYAN}${idx})${RESET} $model"
            eval "MODEL_${idx}='$model'"
            idx=$((idx+1))
        done <<< "$MODELS"
        echo -e "  ${CYAN}${idx})${RESET} ${DIM}Custom Model...${RESET}"
        echo ""
        read -p "  Choose a model (1-$idx): " MODEL_SEL
        if [ "$MODEL_SEL" = "$idx" ]; then
            read -p "  Enter custom model string: " USER_MODEL
        else
            eval "USER_MODEL=\$MODEL_${MODEL_SEL}"
        fi
    fi

    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=${USER_API_KEY}
OPENAI_BASE_URL=https://integrate.api.nvidia.com/v1
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

# ─── Main Flow ──────────────────────────────────────────────
if [ "$goto_loaded" -eq 0 ]; then
    setup_provider
    echo ""
    echo -e "  ${GREEN}[OK] Settings saved!${RESET}"
    echo ""
    # Reload
    ENV_CONTENT="$(cat "$ENV_FILE" 2>/dev/null || true)"
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.* ]] && continue
        [ -z "$key" ] && continue
        export "$key=$value"
    done <<< "$ENV_CONTENT"
fi

# ─── Friendly Provider Name ────────────────────────────────
PROVIDER_NAME="$AI_PROVIDER"
case "$AI_PROVIDER" in
    openai)
        if [[ "$OPENAI_BASE_URL" == *"openrouter"* ]]; then PROVIDER_NAME="OpenRouter"
        elif [[ "$OPENAI_BASE_URL" == *"integrate.api.nvidia.com"* ]]; then PROVIDER_NAME="NVIDIA NIM"
        elif [[ "$OPENAI_BASE_URL" == *"api.openai.com"* ]]; then PROVIDER_NAME="OpenAI"
        elif [[ "$OPENAI_BASE_URL" == *"localhost:11434"* ]]; then PROVIDER_NAME="Ollama"
        fi ;;
    gemini)     PROVIDER_NAME="Google Gemini" ;;
    anthropic)  PROVIDER_NAME="Anthropic Claude" ;;
    ollama)     PROVIDER_NAME="Ollama (Local)" ;;
esac

echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}Claude Code - Ready (Multi-Platform)${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""
echo -e "  ${BOLD}Provider${RESET} : ${GREEN}${PROVIDER_NAME}${RESET}"
echo -e "  ${BOLD}Model${RESET}    : ${GREEN}${AI_DISPLAY_MODEL}${RESET}"
echo -e "  ${BOLD}Data${RESET}     : ${DIM}Portable Mode (No PC Leaks)${RESET}"
echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo ""

# ─── Launch Mode ─────────────────────────────────────────────

CMD_ARGS=""
if [ $QUICK_MODE -eq 1 ]; then
    echo -e "  ${RED}${BOLD}QUICK LAUNCH - Limitless Mode${RESET}"
    echo -e "  ${RED}[!] Commands will execute without confirmation!${RESET}"
    CMD_ARGS="--dangerously-skip-permissions"
else
    echo -e "  ${BOLD}Select Launch Mode:${RESET}"
    echo -e "  ${CYAN}1)${RESET} ${GREEN}Normal Mode${RESET}    ${DIM}- Confirms before running commands${RESET}"
    echo -e "  ${CYAN}2)${RESET} ${RED}Limitless Mode${RESET} ${DIM}- Auto-executes everything (Advanced)${RESET}"
    echo ""
    read -p "  Select mode (1 or 2): " LAUNCH_MODE

    if [ "$LAUNCH_MODE" = "2" ]; then
        echo ""
        echo -e "  ${RED}${BOLD}[!] LIMITLESS MODE ACTIVATED${RESET}"
        CMD_ARGS="--dangerously-skip-permissions"
    else
        echo ""
        echo -e "  ${GREEN}[OK] Normal mode selected.${RESET}"
    fi
fi

# ─── Boot Local Engines (if installed) ──────────────────
SHARED_DIR="$ROOT_DIR/Shared"
LOCAL_STATE="$SHARED_DIR/install-state.json"
LOCAL_ENGINES_UP=0
if [ -f "$LOCAL_STATE" ]; then
    echo -e "  ${CYAN}[~] Booting local AI engines...${RESET}"
    bash "$ROOT_DIR/Mac/start.command" &
    LOCAL_PID=$!
    sleep 5
    LOCAL_ENGINES_UP=1
    echo -e "  ${GREEN}[OK] Local engines starting (chat UI at http://localhost:3333)${RESET}"
    echo ""
fi

if [ $LOCAL_ENGINES_UP -eq 1 ]; then
    echo -e "  ${BOLD}Chat UI${RESET}  : ${GREEN}http://localhost:3333${RESET}  ${DIM}(uncensored local models)${RESET}"
    echo -e "  ${BOLD}Dashboard${RESET}: ${GREEN}http://localhost:3000${RESET}  ${DIM}(OpenClaude web UI)${RESET}"
    echo ""
fi

echo -e "  ${CYAN}[~] Starting AI Engine...${RESET}"
echo ""

# Set PATH for portable tools
export PATH="$NODE_DIR/bin:$PATH"

PROVIDER_ARGS=""
[ -n "$AI_PROVIDER" ] && PROVIDER_ARGS="--provider $AI_PROVIDER"

cd "$BIN_DIR"

# Use portable binary directly (not npx) to avoid conflicts with system-installed claude
OC_BIN="$BIN_DIR/node_modules/.bin/openclaude"
if [ -f "$OC_BIN" ]; then
    "$NODE_DIR/bin/node" "$BIN_DIR/node_modules/@gitlawb/openclaude/bin/openclaude" $PROVIDER_ARGS $CMD_ARGS
else
    npx openclaude $PROVIDER_ARGS $CMD_ARGS
fi

# Cleanup local engines on exit
if [ $LOCAL_ENGINES_UP -eq 1 ]; then
    kill $LOCAL_PID 2>/dev/null
    pkill -f 'ollama' 2>/dev/null
    pkill -f 'llama-server' 2>/dev/null
    pkill -f 'chat_server.py' 2>/dev/null
fi
