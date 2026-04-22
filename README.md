# Portable AI + Code — The Ultimate USB Stick

**Run powerful AI coding agents AND uncensored local chat from any computer — no installation required.** Plug in. Setup once. Code + chat from Windows, Mac, or Linux. Everything lives on the stick.

---

## Your first 5 minutes

1. **Plug in the USB stick** (or download + extract the ZIP to any folder).
2. **Windows:** double-click `Windows\Setup_First_Time.bat`. **Mac:** open Terminal, type `cd /path/to/stick/Mac && bash setup.sh`. **Linux:** `cd /path/to/stick/Linux && bash setup_first_time.sh`.
3. **Follow the prompts.** It downloads everything automatically. Pick the models you want. Say Y to VS Code if you want the IDE. Takes 5-15 minutes depending on your internet.
4. **Run it:** double-click `Windows\Start_AI.bat` (or `bash start_ai.sh` on Mac/Linux).
5. **Open your browser** to `http://localhost:3333` to chat, or `http://localhost:3000` for the coding dashboard. Both URLs appear in big text in the terminal window.

That's it. No accounts, no sign-ups, no installation on your computer. Everything runs from the stick.

---

## What's on the stick

| What | URL | What it does |
|---|---|---|
| **OpenClaude** (terminal + web dashboard) | `http://localhost:3000` | Open-source Claude-Code-style coding agent. Reads/writes files, runs shell commands, analyzes codebases. 6 AI providers. Normal + Limitless (autonomous) modes. |
| **Uncensored Chat** (browser) | `http://localhost:3333` | GPU-accelerated local chat with abliterated models. Install + remove models from the UI. Drop files to attach. Slash commands (`/?`). |
| **Portable VS Code** (optional) | Launch from `tools\vscode\Code.exe` | Full IDE pre-loaded with **Continue** (autocomplete), **Cline** (autonomous agent), **Claude Code**, **GitLens**, **Python**, **Prettier**, **ESLint**. All pointed at your local engine. |

**Coding CLIs baked in:** OpenClaude, Codex (OpenAI), Claude Code CLI (Anthropic), Aider (multi-provider pair programmer). Pick your weapon from the launcher.

All share the same local engine (Ollama on `:11438`). Configure once on Windows — plug into Mac or Linux, everything works.

---

## Quick start

### Windows (first time)

1. Double-click **`Windows\Setup_First_Time.bat`**
2. Follow the prompts:
   - Downloads Node.js + OpenClaude engine (~30 MB)
   - Optionally installs portable Git + Python (~70 MB)
   - Optionally installs GPU-accelerated local models (pick from menu)
   - Optionally downloads VS Code Portable (~120 MB)
3. Done. Run **`Windows\Start_AI.bat`** to launch.

### Windows (every time after)

- **`Windows\Start_AI.bat`** — launches OpenClaude in terminal + boots local engines + chat UI
- **`Windows\Open_Dashboard.bat`** — opens the OpenClaude web dashboard at `http://localhost:3000`
- **`Windows\Change_Model_or_Provider.bat`** — switch AI provider or model
- **`Windows\Setup_Local_Models.bat`** — add more local GPU-accelerated models

### macOS

```bash
cd Mac && bash setup.sh       # first time
bash start_ai.sh              # every time
bash open_dashboard.sh        # web dashboard
```

### Linux

```bash
cd Linux && bash setup_first_time.sh   # first time
bash start_ai.sh                        # every time
bash open_dashboard.sh                  # web dashboard
```

---

## AI providers (for OpenClaude coding agent)

| Provider | Free? | Setup |
|---|---|---|
| **NVIDIA NIM** | Free tier (1000 credits) | [build.nvidia.com](https://build.nvidia.com) |
| **OpenRouter** | Free + paid models | [openrouter.ai](https://openrouter.ai) |
| **Google Gemini** | Free tier | [aistudio.google.com](https://aistudio.google.com) |
| **Anthropic Claude** | Paid | [console.anthropic.com](https://console.anthropic.com) |
| **OpenAI** | Paid | [platform.openai.com](https://platform.openai.com) |
| **Ollama (Local)** | Free + offline | Uses the GPU engine already on the stick — no internet needed |

API keys live in `data/ai_settings.env` on the stick. Move the stick to another computer — your keys come with you.

---

## Local models (for uncensored chat + Ollama provider)

GPU auto-detected at install. Pulls the right engine:

| GPU | Backend |
|---|---|
| Intel Arc (Alchemist, Battlemage, Pro B50) | IPEX-LLM Ollama (SYCL). **63 tok/s verified.** |
| NVIDIA (RTX/Quadro/GeForce) | Stock Ollama (CUDA) |
| AMD Radeon (RDNA 2/3/4) | Stock Ollama (ROCm) |
| AMD Strix Halo / Ryzen AI MAX+ | Stock Ollama (ROCm, gfx1151). **Up to 96 GB VRAM — runs 70B+ locally.** |
| Apple Silicon | Stock Ollama (Metal). **60 tok/s on M1 Pro.** |
| CPU fallback | Stock Ollama |

### Curated model catalog

**Chat (uncensored) — 12 models:**

| Model | Size | Notes |
|---|---|---|
| Gemma 2 2B | 1.6 GB | Recommended first install. Fast on anything. |
| Phi-3.5 Mini | 2.2 GB | Lightweight reasoning |
| Dolphin 8B | 4.9 GB | Balanced uncensored |
| Lexi Llama 3 8B | 4.9 GB | Top-rated uncensored Llama 3 |
| Qwen3 8B | 5.2 GB | Smart all-rounder |
| Gemma 3n 4B | 4.2 GB | MatFormer architecture |
| NemoMix 12B | 7.5 GB | Heavyweight |
| Qwen 14B Uncensored | 8.7 GB | Bigger brain |
| Gemma 4 E2B/E4B (4 variants) | 2.4-4.5 GB | Apple Silicon / Intel Arc only |

**Code generation — 6 models:**

| Model | Size | Notes |
|---|---|---|
| Qwen Coder Mini | 1.1 GB | Tiny. Great for autocomplete via Continue. |
| Qwen Coder 7B | 4.4 GB | Best 7B coder |
| CodeGemma 7B | 5.0 GB | Google's coder. Strong at Rust. |
| StarCoder2 15B | 9.0 GB | Best for Python, JS, non-English langs |
| DeepSeek Coder 16B | 10.4 GB | MoE, fast |
| DeepSeek Coder 33B | 19.9 GB | Heavyweight. Rivals GPT-4. (32 GB+ systems) |

**Reasoning:**

| Model | Size | Notes |
|---|---|---|
| DeepSeek Reasoner 7B | 4.9 GB | Chain-of-thought. Shows its work. |

**Vision / multimodal** (install from the Models button or `ollama pull <name>`):

| Model | Pull command | Size | Notes |
|---|---|---|---|
| LLaVA Mini | `llava-phi3` | 2.9 GB | Smallest working vision |
| LLaVA 7B | `llava:7b` | 4.7 GB | Reliable workhorse |
| Qwen Vision 3B | `qwen2.5-vl:3b` | 2.3 GB | Tiny, sharp. Reads documents. |
| Qwen Vision 8B | `qwen2.5-vl:8b` | 5.5 GB | Best small vision (2026) |
| MiniCPM Vision | `minicpm-v` | 5.5 GB | OCR + charts |
| Moondream 2 | `moondream` | 1.7 GB | Smallest vision. Basic. |

**Embeddings:**

| Model | Size | Notes |
|---|---|---|
| Nomic Embed | 140 MB | Semantic search + RAG |

**Total: 20 installable models + 6 vision models via pull. Install more from the browser: Models button → type a name → Pull.**

Install more models from the browser: open `http://localhost:3333`, click **Models**, type a model name, hit **Pull**.

---

## Cross-platform portability

The `data/` folder is shared across all platforms:

1. Set up your API key on **Windows**
2. Plug the stick into a **Linux** box — settings already there
3. Move to a **Mac** — same thing, zero reconfiguration

Each OS only needs its own `bin/` folder (created by running setup on that platform).

Environment variables `CLAUDE_CONFIG_DIR`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` are all redirected to the stick so nothing leaks to the host.

---

## Privacy + security

- **Zero footprint** — nothing written outside the stick
- **API keys masked** in all display output
- **Approval system** — Normal mode asks before writes/commands; Limitless skips
- **No telemetry** — nothing sent anywhere except your chosen AI provider

---

## Folder layout

```
Portable-AI/
├── Windows/                Setup, Start, Dashboard, Models, Provider, Extensions scripts
│   └── bin/                Node.js, npm packages (OpenClaude, Codex, Claude Code CLI), Git, Python
├── Mac/                    Same (bash scripts + bin/)
├── Linux/                  Same (bash scripts + bin/)
├── Android/                Termux CPU-only (experimental)
├── Shared/                 Cross-platform runtime
│   ├── catalog.json        20 models + 11 GPU backends + 6 vision models
│   ├── chat_server.py      Chat UI proxy (:3333) — debounced saves, warm-up, SSE buffer
│   ├── FastChatUI.html     Browser chat — Models button, slash commands, file drop
│   ├── install-lib.sh      Shared install functions (Mac + Linux)
│   ├── bin/<backend>/      GPU engines (Ollama, IPEX-LLM, llama.cpp SYCL/Vulkan)
│   └── models/             GGUFs + Modelfiles + Ollama registry
├── dashboard/              OpenClaude web dashboard
│   ├── server.mjs          Node.js agent server (:3000) — 6 AI providers, tool-use
│   └── index.html          Dashboard SPA — chat, agent mode, thinking cards
├── data/                   Portable config (shared across ALL platforms)
│   ├── ai_settings.env     API keys + provider config (encrypted on stick)
│   ├── chats/              Agent conversation history
│   └── openclaude/         OpenClaude config + memory
├── tools/
│   ├── vscode/             VS Code Portable (downloaded by setup)
│   │   └── data/           Portable settings, extensions, user data
│   └── vscode-workspace/   Pre-configured workspace file + settings + extension list
└── README.md
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Node.js not found" | Run `Setup_First_Time` |
| Engine offline in chat UI | Run `start.bat` first, or check `Windows\diagnose.bat` |
| Slow on Intel Arc | Update driver: [intel.com/arc-drivers](https://intel.com/arc-drivers), rerun `diagnose.bat` |
| Gemma 4 locks mid-thought | Pull latest `chat_server.py` from this repo (SSE buffer + reasoning fix) |
| Port 3000/3333 in use | Another instance running, or another app on that port |
| API key rejected | Verify at your provider's website |
| Models not showing in chat | Engine not started. Run `start.bat`, then refresh browser. |
| Can't install models from browser | Engine must be running. The Models panel calls Ollama's pull API. |

---

## Credits

- OpenClaude engine by [@gitlawb](https://github.com/gitlawb/openclaude)
- Original portable AI concept by [TechJarves](https://youtube.com/techjarves)
- Intel IPEX-LLM team for the SYCL Ollama build
- bartowski, Mungert, HauhauCS, TrevorJS, Nomic for the GGUFs
- Ollama team for the engine

## License

MIT
<!-- 2026-04-22 -->
