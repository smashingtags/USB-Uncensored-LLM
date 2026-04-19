#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Portable AI USB - First Time Setup (Linux)
# ═══════════════════════════════════════════════════════════

set -e

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[90m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
DATA_DIR="$ROOT_DIR/data"

echo ""
echo -e "${CYAN}    ____            __        __    __        ___    ____${RESET}"
echo -e "${CYAN}   / __ \\____  ____/ /_____ _/ /_  / /__     /   |  /  _/${RESET}"
echo -e "${CYAN}  / /_/ / __ \\/ __/ __/ __ \`/ __ \\/ / _ \\   / /| |  / /  ${RESET}"
echo -e "${CYAN} / ____/ /_/ / / / /_/ /_/ / /_/ / /  __/  / ___ |_/ /   ${RESET}"
echo -e "${CYAN}/_/    \\____/_/  \\__/\\__,_/_.___/_/\\___/  /_/  |_/___/   ${RESET}"
echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}Claude Code - Open Source Setup${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""
echo "  This will download the AI Engine and Core Files"
echo "  directly to this folder so it can run entirely offline."
echo ""

# ─── Internet Check ──────────────────────────────────────────
echo -e "  ${YELLOW}[~] Checking internet connectivity...${RESET}"
if ! curl -s --connect-timeout 5 https://nodejs.org > /dev/null 2>&1; then
    echo -e "  ${RED}[ERROR] No internet connection detected!${RESET}"
    echo "  Please connect to WiFi or Ethernet and try again."
    exit 1
fi
echo -e "  ${GREEN}[OK] Internet connection verified!${RESET}"
echo ""

# ─── Disk Space Check ────────────────────────────────────────
echo -e "  ${YELLOW}[~] Checking available disk space...${RESET}"
FREE_MB=$(df -BM "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{gsub(/M/,"",$4); print $4}')
if [ -z "$FREE_MB" ]; then
    FREE_MB=$(df -m "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{print $4}')
fi
if [ "$FREE_MB" -lt 150 ] 2>/dev/null; then
    echo -e "  ${RED}[ERROR] Not enough disk space!${RESET}"
    echo "  Available: ${FREE_MB} MB  |  Required: ~150 MB"
    exit 1
fi
echo -e "  ${GREEN}[OK] Disk space OK: ${FREE_MB} MB available${RESET}"
echo ""

# ─── Architecture Detection ──────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  NODE_ARCH="x64" ;;
    aarch64) NODE_ARCH="arm64" ;;
    armv7l)  NODE_ARCH="armv7l" ;;
    *)       echo -e "  ${RED}[ERROR] Unsupported architecture: $ARCH${RESET}"; exit 1 ;;
esac

# ─── System Tools Check ─────────────────────────────────────
echo -e "  ${YELLOW}[DIAGNOSTIC] Host System Pre-Check:${RESET}"
HAS_GIT=0; HAS_PYTHON=0
if command -v git &>/dev/null; then HAS_GIT=1; echo -e "  - Git:    ${GREEN}[FOUND]${RESET}"; else echo -e "  - Git:    ${RED}[MISSING]${RESET} ${DIM}(sudo apt install git)${RESET}"; fi
if command -v python3 &>/dev/null; then HAS_PYTHON=1; echo -e "  - Python: ${GREEN}[FOUND]${RESET}"; else echo -e "  - Python: ${RED}[MISSING]${RESET} ${DIM}(sudo apt install python3)${RESET}"; fi
echo -e "  - Arch:   ${GREEN}${ARCH} (${NODE_ARCH})${RESET}"
echo ""

# ─── Variables ───────────────────────────────────────────────
NODE_VERSION="22.14.0"
NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"
NODE_DIR="$BIN_DIR/node-v${NODE_VERSION}-linux-${NODE_ARCH}"

STEP=1
TOTAL_STEPS=2

mkdir -p "$BIN_DIR" "$DATA_DIR"

echo -e "${CYAN}---------------------------------------------------------${RESET}"
echo -e "  ${BOLD}Starting Installation...${RESET}"
echo -e "${CYAN}---------------------------------------------------------${RESET}"
echo ""

# ─── Download Node.js ────────────────────────────────────────
if [ -f "$NODE_DIR/bin/node" ]; then
    echo -e "  ${GREEN}[${STEP}/${TOTAL_STEPS}] Portable Node.js ... already installed [SKIP]${RESET}"
else
    echo -e "  ${CYAN}[${STEP}/${TOTAL_STEPS}] Downloading Portable Node.js (~25MB)...${RESET}"

    DL_OK=0
    for attempt in 1 2 3; do
        [ $attempt -gt 1 ] && echo -e "  ${YELLOW}  [~] Retry attempt ${attempt}/3...${RESET}"
        if curl -# -L -o "$BIN_DIR/$NODE_TARBALL" "$NODE_URL"; then
            DL_OK=1; break
        fi
    done

    if [ $DL_OK -eq 0 ]; then
        echo -e "  ${RED}[FATAL] Failed to download Node.js after 3 attempts!${RESET}"
        exit 1
    fi

    echo -e "  ${CYAN}  Extracting...${RESET}"
    tar xf "$BIN_DIR/$NODE_TARBALL" -C "$BIN_DIR"
    rm -f "$BIN_DIR/$NODE_TARBALL"

    if [ ! -f "$NODE_DIR/bin/node" ]; then
        echo -e "  ${RED}[FATAL] Extraction failed! node binary not found.${RESET}"
        exit 1
    fi
    echo -e "  ${GREEN}  [OK] Node.js installed successfully!${RESET}"
fi
STEP=$((STEP+1))
echo ""

# ─── Install OpenClaude Engine ───────────────────────────────
echo -e "  ${CYAN}[${STEP}/${TOTAL_STEPS}] Installing OpenClaude Engine...${RESET}"

export PATH="$NODE_DIR/bin:$PATH"

cd "$BIN_DIR"
if [ ! -f "$BIN_DIR/package.json" ]; then
    npm init -y > /dev/null 2>&1
fi
npm install @gitlawb/openclaude --no-audit --no-fund --loglevel=error
if [ $? -ne 0 ]; then
    echo -e "  ${RED}[FATAL] OpenClaude installation failed!${RESET}"
    exit 1
fi
echo -e "  ${GREEN}  [OK] OpenClaude engine installed!${RESET}"
STEP=$((STEP+1))
echo ""

# ─── Local AI Models (GPU-accelerated uncensored chat) ───────
echo ""
echo -e "${CYAN}---------------------------------------------------------${RESET}"
echo -e "  ${BOLD}Local AI Setup (GPU-accelerated uncensored models)${RESET}"
echo -e "${CYAN}---------------------------------------------------------${RESET}"
echo ""
echo "  Installs a local GPU-accelerated AI engine and curated"
echo "  uncensored models. Powers the chat UI at localhost:3333."
echo ""
read -p "  Install local AI models? (Y/N): " INSTALL_LOCAL
if [[ "$INSTALL_LOCAL" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "  ${CYAN}[~] Running local model installer...${RESET}"
    bash "$ROOT_DIR/Linux/install.sh"
    echo ""
else
    echo ""
    echo -e "  ${DIM}Skipped. Install later from the chat UI or Linux/install.sh.${RESET}"
    echo ""
fi

# ─── Installation Summary ────────────────────────────────────
NODE_VER=$("$NODE_DIR/bin/node" -v 2>/dev/null || echo "unknown")
OC_VER="unknown"
if [ -f "$BIN_DIR/node_modules/@gitlawb/openclaude/package.json" ]; then
    OC_VER=$(grep '"version"' "$BIN_DIR/node_modules/@gitlawb/openclaude/package.json" | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')
fi
BIN_SIZE=$(du -shm "$BIN_DIR" 2>/dev/null | awk '{print $1}')

echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${GREEN}${BOLD}[DONE] Setup Complete!${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""
echo -e "  ${BOLD}Installation Summary:${RESET}"
echo -e "  ${CYAN}-------------------------------------------------${RESET}"
echo -e "  Node.js      : ${GREEN}${NODE_VER}${RESET}"
echo -e "  OpenClaude   : ${GREEN}v${OC_VER}${RESET}"
echo -e "  Architecture : ${GREEN}${ARCH} (${NODE_ARCH})${RESET}"
if [ $HAS_GIT -eq 1 ]; then echo -e "  Git          : ${GREEN}[FOUND]${RESET}"; else echo -e "  Git          : ${DIM}[NOT INSTALLED]${RESET}"; fi
if [ $HAS_PYTHON -eq 1 ]; then echo -e "  Python       : ${GREEN}[FOUND]${RESET}"; else echo -e "  Python       : ${DIM}[NOT INSTALLED]${RESET}"; fi
echo -e "  ${CYAN}-------------------------------------------------${RESET}"
echo -e "  Total Size   : ${YELLOW}${BIN_SIZE} MB${RESET}"
echo -e "  Location     : ${DIM}${BIN_DIR}${RESET}"
echo ""
echo -e "  ${DIM}You never have to run this again unless you${RESET}"
echo -e "  ${DIM}delete the bin folder.${RESET}"
echo ""

# ─── Auto-Launch Prompt ──────────────────────────────────────
read -p "  Launch start_ai.sh now? (Y/N): " LAUNCH_NOW
if [[ "$LAUNCH_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "  ${CYAN}[~] Launching AI...${RESET}"
    echo ""
    exec bash "$SCRIPT_DIR/start_ai.sh"
else
    echo ""
    echo -e "  ${GREEN}All done! Run './start_ai.sh' whenever you're ready.${RESET}"
    echo ""
fi
