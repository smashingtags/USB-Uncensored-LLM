# Portable AI + Code — The Ultimate USB Stick

**Run powerful AI coding agents AND uncensored local chat from any computer — no installation required.** Plug in. Setup once. Code + chat from Windows, Mac, or Linux. Everything lives on the stick.

---

## What's on the stick

| What | URL | What it does |
|---|---|---|
| **OpenClaude** (terminal + web dashboard) | `http://localhost:3000` | Open-source Claude-Code-style coding agent. Reads/writes files, runs shell commands, analyzes codebases. 6 AI providers. Normal + Limitless (autonomous) modes. |
| **Uncensored Chat** (browser) | `http://localhost:3333` | GPU-accelerated local chat with abliterated models. Install + remove models from the UI. Drop files to attach. Slash commands (`/?`). |
| **Portable VS Code** (optional) | Launch from `tools\vscode\Code.exe` | Full IDE with OpenClaude as the AI assistant. Extensions + settings travel with the stick. |

All three share the same local engine (Ollama on `:11438`). Configure once on Windows — plug into Mac or Linux, everything works.

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

**Chat (uncensored):**

| Model | Size | Notes |
|---|---|---|
| Gemma 2 2B Abliterated | 1.6 GB | Recommended first install |
| Phi-3.5 Mini 3.8B | 2.2 GB | Lightweight reasoning |
| Dolphin 2.9 Llama 3 8B | 4.9 GB | Balanced |
| Qwen3 8B Abliterated | 5.2 GB | Smart |
| Gemma 3n E4B Abliterated | 4.2 GB | MatFormer |
| Gemma 4 E2B (4 variants) | 2.4–4.5 GB | Apple Silicon / Intel Arc only |
| NemoMix Unleashed 12B | 7.5 GB | Heavyweight |

**Code generation:**

| Model | Size | Notes |
|---|---|---|
| Qwen2.5-Coder 7B | 4.4 GB | State-of-the-art 7B coder |
| DeepSeek-Coder-V2 Lite | 10.4 GB | 16B MoE, fast |

**Embeddings:**

| Model | Size | Notes |
|---|---|---|
| Nomic Embed Text v1.5 | 140 MB | Semantic search + RAG |

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
├── Windows/          Setup, Start, Dashboard, Models, Provider scripts
├── Mac/              Same (bash)
├── Linux/            Same (bash)
├── Android/          Termux CPU-only (experimental)
├── Shared/           Cross-platform runtime
│   ├── catalog.json       Models + engines + backends
│   ├── chat_server.py     Chat UI server (:3333)
│   ├── FastChatUI.html    Browser chat interface
│   ├── bin/<backend>/     GPU engines (Ollama variants)
│   └── models/            GGUFs + Ollama registry
├── dashboard/        OpenClaude web UI
│   ├── server.mjs         Node.js agent server (:3000)
│   └── index.html         Dashboard SPA
├── data/             Portable config (shared across OS)
│   ├── ai_settings.env    API keys + provider config
│   └── chats/             Agent conversation history
├── tools/            Optional bundled runtimes
│   ├── vscode/            VS Code Portable (if installed)
│   ├── node/              (in Windows\bin\ — OS-specific)
│   └── git/               (in Windows\bin\ — OS-specific)
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
