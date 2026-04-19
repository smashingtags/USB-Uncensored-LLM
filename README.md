# Eight.ly Forge

**The ultimate portable AI + code-generation stick.** Plug it into any Windows, macOS, or Linux machine, double-click one file, and get:

1. A **local uncensored chat** running on your GPU.
2. A portable **AI coding agent** (open-source Claude-Code-style) that can read files, write files, run commands, and survive between Windows, Linux, and Mac — your chats, keys, and workspace travel with the stick.

Nothing installs on the host. Nothing leaves the machine unless you route a chat through a cloud provider on purpose.

Runs from a USB 3.0 stick, external SSD, or a folder on your main drive.

---

## Visual walkthrough

### 1. The chat UI (`http://localhost:3333`) — empty first launch

![Forge Chat empty](docs/screenshots/01-chat-empty.png)

Left: a list of saved chats + `+ New chat`. Top-center: the model picker (populates once you've installed models). Bottom: the composer. Footer hint: **Enter to send · Shift+Enter newline · /? for commands · drop files to attach**. Engine status sits bottom-left.

### 2. Slash commands (type `/?` in the composer)

![Slash command preview](docs/screenshots/02-chat-slash.png)

Typing `/?` and Enter pops a help alert listing every command: `/clear`, `/export`, `/model <id>`, `/code`, `/system <prompt>`, `/search <text>`. Commands never hit the model — they're handled locally. Full list in the Forge Chat section below.

### 3. Drop a file onto the composer

![Drag-over state](docs/screenshots/03-chat-dragover.png)

The composer outlines in orange when a file is dragged over it. Release to attach.

### 4. After drop — file inlined into the prompt

![After drop](docs/screenshots/04-chat-after-drop.png)

Small text-family files inline directly with a `--- filename ---` banner so the model knows per-file provenance. Binary docs (PDF, DOCX, DOC, RTF) are extracted server-side and their text is inlined the same way.

### 5. Settings drawer

![Chat settings](docs/screenshots/05-chat-settings.png)

Set the system prompt that applies to new chats + the default temperature. Saved to `Shared/chat_data/settings.json` on the stick.

---

### 6. The agent dashboard (`http://localhost:3334`) — first launch

![Forge Agent home](docs/screenshots/06-agent-home.png)

This is the **OpenClaude** coding agent running portably from the stick. What you see:

- **Left sidebar:** `+ New Conversation`, recent chat list, status strip (Provider / Model / Engine / Git / Python).
- **Top bar:** `Chat` | `Setup` | `System` | `Actions` | `Updates`.
- **Main:** quick-start prompts — *Capabilities · Write Code · Debug · Summarize*.
- **Bottom-left:** mode toggle — **Normal** vs **Limitless** (fully-autonomous agentic mode; approve-once tools then go).
- **Bottom-right:** **AGENT MODE** toggle — enables tool-use (read file, write file, run shell).
- **Message box:** send coding tasks in natural language ("read README.md, summarize it, then write a short CONTRIBUTING.md based on the patterns you see").

### 7. Configure providers (first-run: `Configure Now` banner)

![Agent setup](docs/screenshots/07-agent-settings.png)

Pick one (or more) AI providers:
- **NVIDIA NIM** — free tier, no credit card, great for iteration
- **OpenRouter** — hundreds of hosted models, pay-as-you-go
- **Google Gemini / Anthropic Claude / OpenAI** — bring your own key
- **Local Ollama** — uses the engine already running on `:11438` from this stick; no network needed

Keys and settings live in `Shared/chat_data/agent/ai_settings.env` on the stick — move the stick, your config travels with it. The `Export` / `Import` buttons inside the agent UI let you back up / restore the config as a plain text file.

---

## What you get after install

Two web UIs, one runtime:

| URL | What it is | When to use it |
|---|---|---|
| **http://localhost:3333** | **Forge Chat** — fast local chat UI | Fast back-and-forth with local models. Drop files, ask questions, hit `/?` for slash commands. |
| **http://localhost:3334** | **Forge Agent** — portable coding dashboard | Agentic coding: reads/writes files, runs shell commands, multi-provider AI (NVIDIA NIM free, OpenRouter, Gemini, Anthropic, OpenAI, or local Ollama). Your working directory is the stick. |

Both UIs share the same local engine (Ollama on `:11438`, optional llama.cpp SYCL sidecar on `:11441` for Gemma 4 on Intel Arc).

When `start.bat` / `start.command` / `start.sh` runs, you get a banner at the top of the terminal with the exact URLs — local + LAN IP — so you always know where to point your browser (including from your phone on the same network).

---

## Quick start

### Windows
1. `Windows\install.bat` — detects GPU (Intel Arc / NVIDIA / AMD / CPU), picks the right engine, downloads models you select, optionally downloads Node.js portable + MinGit for the agent dashboard.
2. `Windows\start.bat` — boots the engines + chat server. Opens your browser to `http://localhost:3333`. If Node + the agent were installed, the agent dashboard also boots on `:3334`.
3. Optional: `Windows\diagnose.bat` — proves your GPU is actually being used with a 100-token benchmark.

### macOS
1. `Mac/install.command` (double-click)
2. `Mac/start.command`

### Linux
1. `bash Linux/install.sh`
2. `bash Linux/start.sh`

### Android (Termux, CPU-only experiment)
1. `bash Android/install.sh`
2. `bash Android/start.sh`

---

## Forge Chat (`:3333`) — the fast chat UI

Minimal, single-file SPA. Opens to a list of chats + a composer.

**Slash commands** — type `/?` in the composer for the full list:
- `/clear` — wipe current chat
- `/export` — download the current chat as `.md`
- `/model <id>` — switch model (e.g. `/model qwen2.5-coder-7b`)
- `/code` — pick the coder model automatically if one's installed
- `/system <prompt>` — set the system prompt for new chats
- `/search <text>` — grep every saved chat for a string

**File drop / paste** — drop a file onto the composer, or paste from clipboard:
- Text-family files (`.txt .md .py .js .ts .go .rs .sh .json .yaml .csv .log ...`) up to 256 KB: inlined directly into the prompt.
- Anything bigger or non-text (PDF, DOCX, DOC, RTF): extracted server-side via `pdftotext` / `pandoc` / `antiword`, up to 50 MB. If the extractor tool isn't installed, you get a clear message telling you which package to install.

**Keyboard:** Enter sends. Shift+Enter for a newline.

**History:** every chat auto-saves to `Shared/chat_data/chats.json` on the stick. Debounced to once every 5 seconds so USB-speed writes never stall the stream.

---

## Forge Agent (`:3334`) — the portable coding dashboard

Lifted from OpenClaude, re-pathed into `Shared/agent/`. An agentic web dashboard with multi-provider AI and tool-use.

**Providers** (configure once, works on any host):
- **NVIDIA NIM** — free tier, good for fast iteration
- **OpenRouter** — hundreds of hosted models, pay-as-you-go
- **Google Gemini**
- **Anthropic Claude**
- **OpenAI**
- **Local Ollama** (runs against the engine on `:11438` — no network needed)

All keys live in `Shared/agent-data/ai_settings.env` on the stick. Move the stick, your keys come with it. The UI has an Export/Import button so you can copy settings between installs or back them up.

**Agentic mode:** the model can request tools (read_file, write_file, run_shell, list_directory). You approve each action the first time a session calls that tool. Your workspace is the stick by default; change it in the UI.

**What this buys you:**
- Same working directory on Windows, Mac, and Linux — eject the stick, plug into another OS, pick up mid-project.
- Same chat history, same API keys, same system prompts everywhere.
- Bundled Node.js portable (the agent runs on Node 20) and MinGit (portable Git) so the agent can `git clone` / `git commit` without depending on the host's tools.

---

## Install layout (what lives where)

```
eightly-forge/                       <- or whatever name the stick is unzipped under
├── README.md
├── Windows/   install.bat    start.bat    diagnose.bat
├── Mac/       install.command  start.command
├── Linux/     install.sh     start.sh
├── Android/   install.sh     start.sh       (Termux CPU only)
└── Shared/
    ├── catalog.json                 <- source of truth: engines + models + tools
    ├── install-state.json           <- what the installer recorded
    ├── chat_server.py               <- the proxy + chat history + /api/extract (:3333)
    ├── FastChatUI.html              <- the fast chat UI
    ├── chat_data/                   <- your local chats, settings
    │   ├── chats.json
    │   └── settings.json
    ├── bin/
    │   └── <backend>/                <- the engine for the current host
    │       (windows-intel, windows-nvidia, windows-amd, windows-cpu,
    │        windows-intel-llamacpp, windows-amd-llamacpp,
    │        darwin-apple,
    │        linux-cpu, linux-nvidia, linux-amd, linux-amd-llamacpp)
    ├── models/                      <- GGUFs + Modelfiles + Ollama registry
    ├── tools/                       <- bundled runtimes (downloaded by install)
    │   ├── node/                    <- Node.js portable (~30 MB) for the agent
    │   └── git/                     <- MinGit (~50 MB, Windows) for the agent
    └── agent/                       <- the OpenClaude agent (optional)
        ├── server.mjs               <- Node HTTP server, multi-provider, tool-use
        ├── index.html               <- dashboard UI
        └── (data dir at Shared/chat_data/agent/)
```

---

## Model catalog

Curated GGUFs, Q4_K_M quantization, all from trusted uploaders (bartowski, Mungert, HauhauCS, TrevorJS, Nomic).

### Chat / reasoning (uncensored focus)

| Model | Size | Notes |
|---|---|---|
| Gemma 2 2B Abliterated | 1.6 GB | Recommended first install. Fast on any hardware. |
| Phi-3.5 Mini 3.8B | 2.2 GB | Lightweight reasoning. |
| Dolphin 2.9 Llama 3 8B | 4.9 GB | Balanced uncensored. |
| Qwen3 8B Abliterated | 5.2 GB | Smart uncensored all-rounder. |
| Gemma 3n E4B Abliterated (Huihui) | 4.2 GB | MatFormer architecture. |
| Gemma 4 E2B TrevorJS abliterated | 3.2 GB | Apple Silicon (Metal/MLX) or Intel Arc (llama.cpp SYCL). |
| Gemma 4 E2B HauhauCS Aggressive | 2.4 GB | Multimodal-ready GGUF. |
| Gemma 4 E4B HauhauCS Aggressive | 4.5 GB | Multimodal (text/image/video/audio). |
| Gemma 4 E4B TrevorJS abliterated | 4.5 GB | Expert-granular abliteration. |
| NemoMix Unleashed 12B | 7.5 GB | Heavyweight. Needs 16 GB RAM. |

### Code generation

| Model | Size | Notes |
|---|---|---|
| **Qwen2.5-Coder 7B Instruct** | 4.4 GB | State-of-the-art 7B coder. Default pick for `/code`. |
| **DeepSeek-Coder-V2 Lite Instruct** | 10.4 GB | 16B MoE / 2.4B active. Faster than a dense 13B model. |

### Embeddings (for search + RAG)

| Model | Size | Notes |
|---|---|---|
| Nomic Embed Text v1.5 | 140 MB | Semantic search over chat history or any workspace. Served via `/api/embeddings` — no `/api/generate`. |

Gemma 4 routes through upstream **llama.cpp SYCL** on Intel Arc (auto-installed as a secondary engine) and through stock **Ollama v0.21's MLX runtime** on Apple Silicon. IPEX-LLM's Ollama fork doesn't yet ship the gemma4 architecture, so on Arc we load Gemma 4 via the llama.cpp sidecar at `:11441` and keep Ollama on `:11438` for everything else.

---

## GPU support

Auto-detected. Pulls the right engine.

| Host | Backend | Notes |
|---|---|---|
| Intel Arc (Alchemist, Battlemage incl. Pro B50) | IPEX-LLM Ollama (SYCL / Level Zero) | **Verified 63 tok/s on Arc Pro B50** (Gemma 2 2B), 4.86× over CPU. |
| NVIDIA (RTX/Quadro/GeForce) | Stock Ollama (CUDA) | Auto-detects if driver + CUDA runtime are present. |
| AMD Radeon (discrete, RDNA 2/3/4) | Stock Ollama (ROCm) | `HSA_OVERRIDE_GFX_VERSION` may be needed for unlisted cards. |
| **AMD Strix Halo / Ryzen AI MAX+** | Stock Ollama (ROCm, gfx1151) | Up to 96 GB addressable VRAM — runs 70B+ locally on a laptop. |
| AMD (Gemma 4 / any unsupported) | llama.cpp Vulkan sidecar | Auto-falls-back when the ROCm build doesn't know the model arch. |
| Apple Silicon | Stock Ollama / Metal | Pinned to v0.21 for Gemma 4 MLX runtime. **60 tok/s on M1 Pro.** |
| CPU-only fallback | Stock Ollama | Works anywhere x86_64. |

---

## Architecture decisions

- **Single source of truth:** `Shared/catalog.json` describes every engine, model, and bundled tool. Installers read it, launchers read it, the agent dashboard reads it. Add a model by editing JSON.
- **Hybrid engine routing.** Ollama primary on `:11438`, optional llama.cpp sidecar on `:11441` for architectures Ollama doesn't yet support. Chat server proxies both and translates OpenAI ↔ Ollama where needed.
- **No host dependencies.** Ollama / llama.cpp / Node.js / MinGit all ship portable. Python is the only host dep on Windows; the installer grabs embeddable Python 3.12 if it's missing.
- **Chat save debouncing.** History writes are coalesced to once every 5 seconds (or every 10 messages) — USB-speed disk never stalls the stream.
- **Incremental UI render.** The chat UI appends new messages instead of re-rendering the list on every token, and throttles markdown re-parse to one `requestAnimationFrame`.
- **Engine warm-up on boot.** `chat_server.py` fires a 1-token dummy chat at each engine at startup, so the first real message doesn't eat cold-start latency.

---

## LAN access

The top banner in the terminal shows your LAN IP. Hit `http://<your-lan-ip>:3333` from your phone or another PC on the same network. If your firewall blocks inbound on 3333, allow it locally.

---

## Troubleshooting

- **Slow on Windows + Arc.** Run `Windows\diagnose.bat`. Under 25 tok/s on Gemma 2B means your Arc driver is stale — update from <https://intel.com/arc-drivers> and rerun.
- **"Engine offline" in the UI footer.** Chat server can't reach `:11438`. Either `start.bat` hasn't finished booting, or an old Ollama is wedged — `taskkill /f /im ollama.exe` and rerun start.
- **Gemma 4 fails to load on Arc.** The llama.cpp sidecar needs to be installed (automatic when you pick a Gemma 4 model in the installer) and listening on `:11441`. Check with `diagnose.bat` or `netstat -ano | findstr 11441`.
- **Gemma 4 starts thinking then stops.** You're on an old copy of `chat_server.py`. Re-run install or replace `Shared/chat_server.py` from this repo — the fix is in commit `56ac091`.
- **`/api/extract` says a tool isn't installed.** You tried to drop a PDF/DOCX/DOC and the host is missing `pdftotext` / `pandoc` / `antiword`. Install: `apt install poppler-utils pandoc antiword` (Linux), `brew install poppler pandoc` (Mac), `choco install xpdf-utils pandoc` (Windows).
- **Agent dashboard not loading on `:3334`.** Node.js wasn't downloaded by install. Re-run `install.bat` with internet connectivity; Node portable (~30 MB) pulls into `Shared/tools/node/` and `start.bat` will boot the agent next launch.
- **Port conflict on `:11434` or `:3333`.** Forge deliberately uses `:11438` for the engine to avoid collision with an existing Ollama. If another chat UI owns `:3333`, edit `start.bat`'s `ELY_CHAT_PORT`.

---

## Credits

- Forked from `TechJarves/USB-Uncensored-LLM` and refactored into Eight.ly Forge.
- Agent dashboard lifted from the **OpenClaude** multi-platform project.
- Intel IPEX-LLM team for the SYCL Ollama build.
- bartowski, Mungert, HauhauCS, TrevorJS, Nomic for the GGUFs.
- Ollama team for the engine and the v0.21 MLX Gemma 4 runtime.
- llama.cpp project for the Vulkan + SYCL backends.

---

## Sister products

- **Eight.ly OS** — the NAS operating system. Ships with **Nova**, the always-on server-resident version of this same chat stack. Same catalog shape, same engines, same UX.
- **Eight.ly Professional** — self-hosted NAS application platform.
- **NeuroHelper** (iOS) — mobile companion that shares Nova's persona.

## License

MIT. See `LICENSE`.

---

*Eight.ly Forge is uncompromising about computational freedom. The curated models are abliterated or aggressively uncensored — they won't moralize, lecture, or refuse. Use responsibly.*
