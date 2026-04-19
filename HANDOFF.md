# HANDOFF — Ultimate Portable AI Installer

**Branch:** `ultimate-installer` (branched from `56ac091`, pre-Forge mess)
**Date:** 2026-04-19
**Repo:** `smashingtags/USB-Uncensored-LLM` (GitHub name stays; product name changes)

## THE VISION (Michael's words, not mine)

One USB stick. Three things:

1. **Chat UI** (like ChatGPT) — talks to local uncensored GPU-accelerated models. Can install/remove models FROM the UI (no bat files). Drag-drop files. Slash commands.
2. **OpenClaude** inside **Portable VS Code** — real IDE + AI coding agent. Reads/writes files, runs shell, multi-provider (NIM free / OpenRouter / Gemini / Anthropic / OpenAI / local Ollama). All config + chats portable across Windows/Mac/Linux via shared `data/` folder.
3. **One installer** — GPU detect (Intel Arc / NVIDIA / AMD / Strix Halo / Apple Silicon / CPU), downloads engines + models + Node.js + VS Code Portable + MinGit. Everything self-contained.

Cross-platform: configure once on Windows, plug into Mac, everything works. `data/` folder shared. Each platform only needs its own `bin/` (engine binaries).

## WHAT 4.7 DID WRONG (14 PRs merged to main, all wrong direction)

Treated OpenClaude as a sidebar dashboard bolted onto the old chat UI. Renamed everything "Forge." Two UIs on two ports (:3333 chat, :3334 agent). Inverted architecture. Michael wanted OpenClaude AS the product with the GPU engine plugged in, not the other way around.

## WHAT TO KEEP from those 14 PRs (re-apply by hand, don't cherry-pick)

1. AMD + Strix Halo GPU detection in catalog.json + install scripts (PR #3)
2. SSE buffer fix in chat_server.py (PR #2)
3. Gemma 4 reasoning_content merge in chat_server.py (PR #4)
4. Debounced chat saves + engine warm-up in chat_server.py (from Phase B)
5. Coder models in catalog: Qwen2.5-Coder 7B, DeepSeek-Coder-V2 Lite, Nomic Embed

## SOURCE MATERIAL (all at /tmp/stick-origins/)

| ZIP | What | Role in the product |
|---|---|---|
| `USB-Uncensored-LLM-main.zip` | Original TechJarves chat stick | **Chat UI base** (FastChatUI.html + chat_server.py) |
| `OpenClaude-Multi-Platform-main.zip` | Portable Claude Code clone | **Coding agent** (dashboard/server.mjs + index.html, per-platform scripts) |
| `Portable-AI-USB-main.zip` | Older TechJarves installer | Reference for install UX patterns |
| `Local_AI_MultiPlatform-main.zip` | Flutter native AI chat app | Future reference (native GUI via llamadart). Not used in this build. |
| `Openclaw-Termux-NoRoot-main.zip` | Android Telegram bot | Not used. |

Also on Mac: originals at `~/.openclaw/Shared With Claude/Eightly-stick-beginnings/`

## CORRECT ARCHITECTURE

```
Ultimate-AI-Stick/
├── install.bat / install.command / install.sh    <- ONE entry point per OS
│     Step 1: GPU detect
│     Step 2: Download Ollama engine (catalog-driven, per-GPU)
│     Step 3: Download models (user picks from menu)
│     Step 4: Download Node.js portable
│     Step 5: Download VS Code Portable (Windows) / code-server (Mac/Linux)
│     Step 6: Download MinGit (Windows)
│     Step 7: Install OpenClaude as VS Code extension / terminal tool
│     Step 8: Smoke test
│
├── start.bat / start.command / start.sh          <- ONE entry point per OS
│     1. Boot Ollama engine on :11438
│     2. Boot llama.cpp sidecar on :11441 (if Gemma 4 installed)
│     3. Boot chat_server.py on :3333 (chat UI)
│     4. Boot OpenClaude dashboard on :3000 (or inside VS Code)
│     5. Print banner with ALL URLs + LAN IP
│     6. Open browser
│
├── Shared/                                       <- cross-platform runtime
│   ├── catalog.json
│   ├── chat_server.py + FastChatUI.html          <- chat UI
│   ├── bin/<backend>/                            <- engines
│   ├── models/                                   <- GGUFs
│   └── chat_data/                                <- portable chats + settings
│
├── data/                                         <- OpenClaude portable config
│   ├── ai_settings.env                           <- API keys (encrypted on stick)
│   └── chats/                                    <- agent chat sessions
│
├── dashboard/                                    <- OpenClaude web UI
│   ├── server.mjs
│   └── index.html
│
├── tools/                                        <- bundled runtimes
│   ├── node/                                     <- Node.js portable
│   ├── git/                                      <- MinGit (Windows)
│   └── vscode/                                   <- VS Code Portable (or code-server)
│
└── Windows/ Mac/ Linux/                          <- platform-specific bins + scripts
    └── bin/                                      <- created by install (Node, etc.)
```

## WHAT'S DONE ON THIS BRANCH (8 commits, all pushed)

1. `f3cd7b7` — Restructured folder: OpenClaude dashboard + per-platform scripts copied in alongside existing chat UI
2. `c15d90c` — Merged install flows: Windows Setup_First_Time.bat chains into install-core.ps1, Start_AI.bat boots local engines + chat UI alongside OpenClaude
3. `e22a198` — Re-applied useful fixes: debounced saves, warm-up, coder models (Qwen2.5-Coder 7B, DeepSeek-Coder-V2 Lite, Nomic Embed)
4. `23f7a0c` — In-browser model management: Models button in chat UI, pull + delete without bat files
5. `22c4e7a` — VS Code Portable download step in Windows Setup_First_Time.bat
6. `ad16fd8` — README rewrite for the unified product
7. `8f5a49f` — Mac + Linux parity: setup chains into local-model install, start_ai boots engines, Ollama provider redirects to :11438

## WHAT'S LEFT

- Wire OpenClaude as a pre-installed extension inside portable VS Code (currently VS Code downloads but user must open terminal manually to use OpenClaude)
- End-to-end test on amd-beast (Windows + Intel Arc)
- End-to-end test on Mac Mini (Apple Silicon)
- Replace main when Michael approves the branch
