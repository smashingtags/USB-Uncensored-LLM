#!/usr/bin/env python3
"""
Portable AI Chat Server
=======================
A zero-dependency Python HTTP server that:
  1. Serves the FastChatUI.html web interface
  2. Saves/loads chat history as JSON files on the USB drive
  3. Proxies all Ollama API requests (eliminates CORS issues)

Works on Windows, macOS, and Linux without installing anything.
"""

import http.server
import json
import os
import sys
import urllib.request
import urllib.error
import threading
import webbrowser
import time
import platform
import ctypes
import ctypes.util
from urllib.parse import urlparse

# Optional: psutil for hardware stats (graceful fallback to native APIs if not installed)
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

# Configuration
# Eight.ly Stick runs Ollama on :11438 by default. For models whose architecture
# isn't in our Ollama build yet (Gemma 4 on Intel Arc), a secondary llama.cpp
# server runs on :11441 and we route per-model.
CHAT_SERVER_PORT    = int(os.environ.get("ELY_CHAT_PORT", "3333"))
OLLAMA_HOST         = os.environ.get("ELY_OLLAMA_URL",   "http://127.0.0.1:11438")
LLAMACPP_HOST       = os.environ.get("ELY_LLAMACPP_URL", "").strip()
LLAMACPP_MODEL_ID   = os.environ.get("ELY_LLAMACPP_MODEL_ID", "").strip()

# Legacy --llama-cpp flag kept for back-compat: forces all traffic through llama.cpp
LLAMA_CPP_MODE = "--llama-cpp" in sys.argv
if LLAMA_CPP_MODE:
    OLLAMA_HOST = "http://127.0.0.1:8080"

# Always resolve paths relative to THIS script's location (the USB drive)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHATS_DIR = os.path.join(SCRIPT_DIR, "chat_data")
CHATS_FILE = os.path.join(CHATS_DIR, "chats.json")
SETTINGS_FILE = os.path.join(CHATS_DIR, "settings.json")
HTML_FILE = os.path.join(SCRIPT_DIR, "FastChatUI.html")

_SAVE_DEBOUNCE_SECONDS = float(os.environ.get("ELY_SAVE_DEBOUNCE_SECONDS", "5"))
_CHATS_LOCK = threading.Lock()
_CHATS_PENDING = {"data": None, "dirty": False, "since": 0.0}


def _chats_flusher():
    os.makedirs(CHATS_DIR, exist_ok=True)
    while True:
        time.sleep(_SAVE_DEBOUNCE_SECONDS)
        with _CHATS_LOCK:
            if not _CHATS_PENDING["dirty"]:
                continue
            data = _CHATS_PENDING["data"]
            _CHATS_PENDING["dirty"] = False
        try:
            tmp = CHATS_FILE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
            os.replace(tmp, CHATS_FILE)
        except Exception as e:
            sys.stderr.write(f"[chat_server] chat flush failed: {e}\n")


def _warmup_engines():
    try:
        time.sleep(2)
        payload = json.dumps({"messages": [{"role": "user", "content": "hi"}], "stream": False, "options": {"num_predict": 1}}).encode()
        try:
            req = urllib.request.Request(OLLAMA_HOST + "/api/tags", method="GET")
            tags = json.loads(urllib.request.urlopen(req, timeout=3).read())
            models = [m.get("model") or m.get("name") for m in tags.get("models", [])]
            if models:
                warm = json.dumps({"model": models[0], "messages": [{"role": "user", "content": "hi"}], "stream": False, "options": {"num_predict": 1}}).encode()
                r = urllib.request.Request(OLLAMA_HOST + "/api/chat", data=warm, headers={"Content-Type": "application/json"}, method="POST")
                urllib.request.urlopen(r, timeout=60).read()
                sys.stderr.write(f"[chat_server] warmup: ollama {models[0]} ok\n")
        except Exception as e:
            sys.stderr.write(f"[chat_server] warmup: ollama skipped ({e})\n")
        if LLAMACPP_HOST and LLAMACPP_MODEL_ID:
            try:
                warm = json.dumps({"model": LLAMACPP_MODEL_ID, "messages": [{"role": "user", "content": "hi"}], "stream": False, "max_tokens": 1}).encode()
                r = urllib.request.Request(LLAMACPP_HOST + "/v1/chat/completions", data=warm, headers={"Content-Type": "application/json"}, method="POST")
                urllib.request.urlopen(r, timeout=120).read()
                sys.stderr.write(f"[chat_server] warmup: llama-server {LLAMACPP_MODEL_ID} ok\n")
            except Exception as e:
                sys.stderr.write(f"[chat_server] warmup: llama-server skipped ({e})\n")
    except Exception as e:
        sys.stderr.write(f"[chat_server] warmup thread crashed: {e}\n")


# ── Pure-Python Hardware Stats (no psutil needed) ──────────────
_cpu_times_last = None  # (idle, total) from previous sample

def _get_hw_stats():
    """Return (cpu_percent, ram_percent) using only stdlib / ctypes."""
    global _cpu_times_last  # must be at top of function, before any branch uses it

    if HAS_PSUTIL:
        cpu = round(psutil.cpu_percent(interval=0.25), 1)
        ram = round(psutil.virtual_memory().percent, 1)
        return cpu, ram

    plat = platform.system()

    # ── Windows ──────────────────────────────────────────────────
    if plat == "Windows":
        # RAM via GlobalMemoryStatusEx
        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [
                ("dwLength",                ctypes.c_ulong),
                ("dwMemoryLoad",            ctypes.c_ulong),
                ("ullTotalPhys",            ctypes.c_ulonglong),
                ("ullAvailPhys",            ctypes.c_ulonglong),
                ("ullTotalPageFile",        ctypes.c_ulonglong),
                ("ullAvailPageFile",        ctypes.c_ulonglong),
                ("ullTotalVirtual",         ctypes.c_ulonglong),
                ("ullAvailVirtual",         ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]
        msx = MEMORYSTATUSEX()
        msx.dwLength = ctypes.sizeof(msx)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(msx))
        ram = float(msx.dwMemoryLoad)

        # CPU via GetSystemTimes (idle/kernel/user tick counts)
        FILETIME = ctypes.c_ulonglong
        idle, kern, user = FILETIME(), FILETIME(), FILETIME()
        ctypes.windll.kernel32.GetSystemTimes(
            ctypes.byref(idle), ctypes.byref(kern), ctypes.byref(user))
        idle_v = idle.value
        total_v = kern.value + user.value
        if _cpu_times_last is None:
            # First call — sleep briefly and sample again
            time.sleep(0.25)
            idle2, kern2, user2 = FILETIME(), FILETIME(), FILETIME()
            ctypes.windll.kernel32.GetSystemTimes(
                ctypes.byref(idle2), ctypes.byref(kern2), ctypes.byref(user2))
            d_idle  = idle2.value - idle_v
            d_total = (kern2.value + user2.value) - total_v
            _cpu_times_last = (idle2.value, kern2.value + user2.value)
        else:
            prev_idle, prev_total = _cpu_times_last
            d_idle  = idle_v  - prev_idle
            d_total = total_v - prev_total
            _cpu_times_last = (idle_v, total_v)

        cpu = round((1.0 - d_idle / max(d_total, 1)) * 100.0, 1)
        cpu = max(0.0, min(100.0, cpu))
        return cpu, ram

    # ── Linux ─────────────────────────────────────────────────────
    elif plat == "Linux":
        # RAM
        ram = 0.0
        try:
            with open("/proc/meminfo") as f:
                mem = {}
                for line in f:
                    parts = line.split()
                    if len(parts) >= 2:
                        mem[parts[0].rstrip(":")] = int(parts[1])
            total = mem.get("MemTotal", 1)
            avail = mem.get("MemAvailable", total)
            ram = round((1 - avail / total) * 100, 1)
        except Exception:
            pass
        # CPU via /proc/stat delta
        cpu = 0.0
        try:
            def read_cpu():
                with open("/proc/stat") as f:
                    parts = f.readline().split()
                vals = [int(x) for x in parts[1:]]
                idle = vals[3]
                total = sum(vals)
                return idle, total
            if _cpu_times_last is None:
                i1, t1 = read_cpu()
                time.sleep(0.25)
                i2, t2 = read_cpu()
            else:
                i1, t1 = _cpu_times_last
                i2, t2 = read_cpu()
            _cpu_times_last = (i2, t2)
            d_idle  = i2 - i1
            d_total = t2 - t1
            cpu = round((1 - d_idle / max(d_total, 1)) * 100, 1)
        except Exception:
            pass
        return cpu, ram

    # ── macOS ─────────────────────────────────────────────────────
    else:
        # User requested to skip macOS usage to avoid any potential permission/execution issues
        cpu = 0.0
        ram = 0.0
        return cpu, ram


def ensure_data_dir():
    """Create the chat_data folder on the USB if it doesn't exist."""
    os.makedirs(CHATS_DIR, exist_ok=True)
    if not os.path.exists(CHATS_FILE):
        with open(CHATS_FILE, "w", encoding="utf-8") as f:
            json.dump([], f)
    if not os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump({"systemPrompt": "", "temperature": 0.7}, f)


class ChatHandler(http.server.BaseHTTPRequestHandler):
    """Handles all HTTP requests for the Portable AI Chat."""

    def log_message(self, format, *args):
        """Print all requests for easy debugging."""
        msg = format % args
        ts = time.strftime("%H:%M:%S")
        # Colour-code by status: errors red, warnings yellow, ok green
        if "404" in msg or "500" in msg or "502" in msg:
            prefix = "  \033[91m[ERR]\033[0m"
        elif "200" in msg or "204" in msg:
            prefix = "  \033[92m[ OK]\033[0m"
        else:
            prefix = "  \033[93m[---]\033[0m"
        print(f"{prefix} {ts}  {msg}")

    # ── CORS headers ───────────────────────────────────────────
    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(204)
        self._cors_headers()
        self.end_headers()

    # ── Routing ────────────────────────────────────────────────
    def do_GET(self):
        path = urlparse(self.path).path

        # Serve the main UI
        if path == "/" or path == "/index.html":
            self._serve_html()

        # Chat data API
        elif path == "/api/chats":
            self._get_chats()

        # Settings API
        elif path == "/api/settings":
            self._get_settings()

        # Catalog API — serves the full model catalog for the UI to browse
        elif path == "/api/catalog":
            self._get_catalog()

        # Hardware stats API
        elif path == "/api/stats":
            self._get_stats()

        # Proxy Ollama API
        elif path.startswith("/ollama/"):
            self._proxy_ollama("GET")

        else:
            # Try serving static files from SCRIPT_DIR
            self._serve_static(path)

    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/api/chats":
            self._save_chats()

        elif path == "/api/settings":
            self._save_settings()

        elif path == "/api/install-model":
            self._install_catalog_model()

        # Proxy Ollama API
        elif path.startswith("/ollama/"):
            self._proxy_ollama("POST")

        else:
            self.send_response(404)
            self._cors_headers()
            self.end_headers()

    def do_DELETE(self):
        path = urlparse(self.path).path
        if path.startswith("/ollama/"):
            self._proxy_ollama("DELETE")
        else:
            self.send_response(404)
            self._cors_headers()
            self.end_headers()

    # ── Serve HTML ─────────────────────────────────────────────
    def _serve_html(self):
        try:
            with open(HTML_FILE, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self._cors_headers()
            self.end_headers()
            self.wfile.write(content)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"FastChatUI.html not found.")

    def _serve_static(self, path):
        """Serve static files (CSS, JS, images) from SCRIPT_DIR."""
        safe_path = os.path.normpath(path.lstrip("/"))
        full_path = os.path.join(SCRIPT_DIR, safe_path)

        # Security: don't allow path traversal
        if not full_path.startswith(SCRIPT_DIR):
            self.send_response(403)
            self.end_headers()
            return

        if os.path.isfile(full_path):
            ext = os.path.splitext(full_path)[1].lower()
            mime_types = {
                ".html": "text/html", ".css": "text/css", ".js": "application/javascript",
                ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg",
                ".svg": "image/svg+xml", ".ico": "image/x-icon"
            }
            content_type = mime_types.get(ext, "application/octet-stream")
            with open(full_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self._cors_headers()
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_response(404)
            self.end_headers()

    # ── Catalog ────────────────────────────────────────────────
    def _get_catalog(self):
        catalog_path = os.path.join(SCRIPT_DIR, "catalog.json")
        try:
            with open(catalog_path, "r", encoding="utf-8") as f:
                data = f.read()
        except FileNotFoundError:
            data = '{"models":[]}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors_headers()
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

    # ── Model Install (GGUF download + ollama create) ──────────
    def _install_catalog_model(self):
        import subprocess
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            req = json.loads(body)
            model_id = req.get("id", "")
        except:
            self._respond_json({"error": "bad request"}, 400); return

        catalog_path = os.path.join(SCRIPT_DIR, "catalog.json")
        try:
            catalog = json.load(open(catalog_path))
        except:
            self._respond_json({"error": "catalog not found"}, 500); return

        model = None
        for m in catalog.get("models", []):
            if m["id"] == model_id:
                model = m; break
        if not model:
            self._respond_json({"error": f"model {model_id} not in catalog"}, 404); return

        models_dir = os.path.join(SCRIPT_DIR, "models")
        os.makedirs(models_dir, exist_ok=True)
        gguf_path = os.path.join(models_dir, model["file"])

        # Step 1: Download GGUF if not present
        if not os.path.exists(gguf_path) or os.path.getsize(gguf_path) < model.get("sizeBytes", 1) * 0.9:
            sys.stderr.write(f"[install] downloading {model['name']} ({model['sizeLabel']})...\n")
            try:
                dl_req = urllib.request.Request(model["url"])
                dl_req.add_header("User-Agent", "Mozilla/5.0")
                with urllib.request.urlopen(dl_req, timeout=1800) as resp:
                    with open(gguf_path + ".tmp", "wb") as f:
                        while True:
                            chunk = resp.read(1024 * 1024)
                            if not chunk:
                                break
                            f.write(chunk)
                os.replace(gguf_path + ".tmp", gguf_path)
                sys.stderr.write(f"[install] downloaded {model['file']}\n")
            except Exception as e:
                try: os.remove(gguf_path + ".tmp")
                except: pass
                self._respond_json({"error": f"download failed: {e}"}, 500); return

        # Step 2: Create Modelfile
        sys_prompt = model.get("systemPrompt", "").replace('"', '\\"')
        temp = model.get("params", {}).get("temperature", 0.7)
        top_p = model.get("params", {}).get("top_p", 0.9)
        modelfile_path = os.path.join(models_dir, f"Modelfile-{model_id}")
        with open(modelfile_path, "w") as f:
            f.write(f"FROM ./{model['file']}\n")
            f.write(f"PARAMETER temperature {temp}\n")
            f.write(f"PARAMETER top_p {top_p}\n")
            if sys_prompt:
                f.write(f'SYSTEM "{sys_prompt}"\n')

        # Step 3: ollama create
        ollama_host = OLLAMA_HOST.replace("http://", "").replace("https://", "")
        env = dict(os.environ)
        env["OLLAMA_HOST"] = ollama_host
        sys.stderr.write(f"[install] running ollama create {model_id}...\n")
        try:
            result = subprocess.run(
                ["ollama", "create", model_id, "-f", modelfile_path],
                cwd=models_dir, env=env, capture_output=True, text=True, timeout=300
            )
            if result.returncode != 0:
                # Try with full path to ollama
                ollama_bin = None
                for d in os.listdir(os.path.join(SCRIPT_DIR, "bin")):
                    candidate = os.path.join(SCRIPT_DIR, "bin", d, "ollama.exe" if os.name == "nt" else "ollama")
                    if os.path.exists(candidate):
                        ollama_bin = candidate; break
                if ollama_bin:
                    result = subprocess.run(
                        [ollama_bin, "create", model_id, "-f", modelfile_path],
                        cwd=models_dir, env=env, capture_output=True, text=True, timeout=300
                    )
            if result.returncode != 0:
                self._respond_json({"error": f"ollama create failed: {result.stderr[:300]}"}, 500); return
        except FileNotFoundError:
            self._respond_json({"error": "ollama binary not found"}, 500); return

        sys.stderr.write(f"[install] {model['name']} installed successfully\n")
        self._respond_json({"ok": True, "model": model_id, "name": model["name"]})

    def _respond_json(self, obj, status=200):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self._cors_headers()
        self.end_headers()
        self.wfile.write(data)

    # ── Chat Persistence ───────────────────────────────────────
    def _get_chats(self):
        with _CHATS_LOCK:
            pending = _CHATS_PENDING["data"] if _CHATS_PENDING["dirty"] else None
        if pending is not None:
            data = json.dumps(pending, ensure_ascii=False, separators=(",", ":"))
        else:
            try:
                with open(CHATS_FILE, "r", encoding="utf-8") as f:
                    data = f.read()
            except (FileNotFoundError, json.JSONDecodeError):
                data = "[]"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors_headers()
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

    def _save_chats(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            chats = json.loads(body)
        except Exception as e:
            self.send_response(500); self._cors_headers(); self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode()); return
        with _CHATS_LOCK:
            _CHATS_PENDING["data"] = chats
            _CHATS_PENDING["dirty"] = True
            _CHATS_PENDING["since"] = time.time()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors_headers()
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True}).encode())

    def _get_settings(self):
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                data = f.read()
        except (FileNotFoundError, json.JSONDecodeError):
            data = "{}"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors_headers()
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

    def _save_settings(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            settings = json.loads(body)
            with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
                json.dump(settings, f, ensure_ascii=False, indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"ok": True}).encode())
        except Exception as e:
            self.send_response(500)
            self._cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    # ── Hardware Stats ─────────────────────────────────────────
    def _get_stats(self):
        """Return CPU % and RAM % as JSON. Works with no external packages."""
        try:
            cpu, ram = _get_hw_stats()
            data = json.dumps({"cpu_percent": cpu, "ram_percent": ram, "has_psutil": HAS_PSUTIL})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors_headers()
            self.end_headers()
            self.wfile.write(data.encode())
        except Exception as e:
            self.send_response(500)
            self._cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    # ── Ollama Proxy (streaming-aware, hybrid-routing) ─────────
    def _proxy_ollama(self, method):
        """Top-level router. Picks a handler per path + routing decision."""
        ollama_path = self.path[len("/ollama"):]
        body = None
        n = int(self.headers.get("Content-Length", 0))
        if n > 0:
            body = self.rfile.read(n)

        try:
            # --- /api/tags: three flavors (legacy llama.cpp, hybrid, pure Ollama)
            if ollama_path == "/api/tags":
                if LLAMA_CPP_MODE:
                    return self._respond_json({"models": [{"name": "local-llama-model"}]})
                if LLAMACPP_HOST and LLAMACPP_MODEL_ID:
                    return self._handle_hybrid_tags()
                return self._proxy_passthrough(method, OLLAMA_HOST + ollama_path, body, is_stream=False)

            # --- /api/chat + /api/generate: route per-model to llama.cpp or Ollama
            if ollama_path in ("/api/chat", "/api/generate"):
                if self._should_route_to_llamacpp(body):
                    return self._handle_llamacpp_chat(body)
                return self._proxy_passthrough(
                    method, OLLAMA_HOST + ollama_path, body,
                    is_stream=True,
                )

            # --- default: straight proxy
            return self._proxy_passthrough(method, OLLAMA_HOST + ollama_path, body, is_stream=False)

        except urllib.error.HTTPError as e:
            self.send_response(e.code); self._cors_headers(); self.end_headers()
            try: self.wfile.write(e.read())
            except Exception: pass
        except urllib.error.URLError as e:
            self.send_response(502); self._cors_headers(); self.end_headers()
            self.wfile.write(json.dumps({"error": f"Cannot reach engine: {e.reason}"}).encode())
        except Exception as e:
            self.send_response(500); self._cors_headers(); self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def _respond_json(self, obj, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self._cors_headers()
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

    def _should_route_to_llamacpp(self, body):
        if LLAMA_CPP_MODE:
            return True
        if not (LLAMACPP_HOST and LLAMACPP_MODEL_ID and body):
            return False
        try:
            req_model = (json.loads(body).get("model") or "").split(":")[0]
        except Exception:
            return False
        return req_model == LLAMACPP_MODEL_ID

    def _handle_hybrid_tags(self):
        """GET /ollama/api/tags -> Ollama's list + synthetic llama-server entry."""
        try:
            resp = urllib.request.urlopen(urllib.request.Request(OLLAMA_HOST + "/api/tags"), timeout=5)
            data = json.loads(resp.read().decode())
        except Exception:
            data = {"models": []}
        existing = {m.get("name", "").split(":")[0] for m in data.get("models", [])}
        if LLAMACPP_MODEL_ID not in existing:
            data.setdefault("models", []).append({
                "name":        f"{LLAMACPP_MODEL_ID}:latest",
                "model":       f"{LLAMACPP_MODEL_ID}:latest",
                "size":        0,
                "modified_at": "1970-01-01T00:00:00Z",
                "details":     {"family": "gemma4", "format": "gguf", "parameter_size": "llama.cpp"},
            })
        self._respond_json(data)

    def _handle_llamacpp_chat(self, body):
        """POST /ollama/api/chat routed to llama-server with Ollama<->OpenAI translation."""
        ollama_req = json.loads(body) if body else {}
        is_stream  = bool(ollama_req.get("stream", True))
        opts = ollama_req.get("options") or {}
        openai_req = {
            "messages":    ollama_req.get("messages", []),
            "stream":      is_stream,
            "temperature": opts.get("temperature", 0.7),
            "top_p":       opts.get("top_p", 0.95),
            "max_tokens":  opts.get("num_predict", 512),
        }
        host = LLAMACPP_HOST or OLLAMA_HOST
        req = urllib.request.Request(
            host + "/v1/chat/completions",
            data=json.dumps(openai_req).encode(),
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        resp = urllib.request.urlopen(req, timeout=600)

        if not is_stream:
            return self._emit_ollama_from_openai_json(resp)
        return self._stream_openai_sse_as_ollama_ndjson(resp)

    def _emit_ollama_from_openai_json(self, resp):
        """Translate a single non-streaming OpenAI chat completion into Ollama's chat format."""
        raw = resp.read()
        try:
            oj = json.loads(raw.decode())
            msg = (oj.get("choices") or [{}])[0].get("message", {}) or {}
            # Gemma 4 (and other DeepSeek-style reasoners) may leak the answer into
            # reasoning_content when llama-server's --reasoning-format isn't "none".
            content = msg.get("content") or msg.get("reasoning_content") or ""
            timings = oj.get("timings") or {}
            usage   = oj.get("usage")   or {}
            eval_count = timings.get("predicted_n") or usage.get("completion_tokens") or 0
            eval_ns    = int((timings.get("predicted_ms") or 0) * 1_000_000)
            self._respond_json({
                "model":             oj.get("model", ""),
                "created_at":        "",
                "message":           {"role": "assistant", "content": content},
                "done":              True,
                "done_reason":       (oj.get("choices") or [{}])[0].get("finish_reason", "stop"),
                "total_duration":    eval_ns,
                "eval_count":        eval_count,
                "eval_duration":     eval_ns,
                "prompt_eval_count": usage.get("prompt_tokens", 0),
            })
        except Exception as e:
            self._respond_json(
                {"error": f"translate failed: {e}",
                 "raw": raw.decode(errors="ignore")[:500]},
                status=502,
            )

    def _stream_openai_sse_as_ollama_ndjson(self, resp):
        """Stream SSE chunks from llama-server as Ollama-style newline-delimited JSON.

        Buffers across reads — a single `data: {...}` line can span multiple
        socket reads. Split on \\n only AFTER accumulating, and keep the
        trailing partial as the seed for the next iteration.

        Gemma 4 (and other DeepSeek-style reasoners) may emit reasoning tokens
        in `delta.reasoning_content` instead of (or alongside) `delta.content`,
        even with `--reasoning-format none` — behavior varies by llama.cpp
        build. We transcode both streams into a single `content` stream using
        `<think>...</think>` markers that the UI already collapses. Without
        this merge, thinking chunks that land only in reasoning_content get
        silently dropped and the chat appears to hang mid-thought."""
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self._cors_headers()
        self.end_headers()
        buf = ""
        done = False
        in_think = False  # True while we're inside an open <think> block

        def emit(text):
            self.wfile.write((json.dumps({"message": {"role": "assistant", "content": text}, "done": False}) + "\n").encode())
            self.wfile.flush()

        while not done:
            chunk = resp.read(4096)
            if not chunk:
                break
            buf += chunk.decode(errors="ignore")
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                line = line.strip()
                if not line or not line.startswith("data: "):
                    continue
                data = line[6:].strip()
                if data == "[DONE]":
                    try:
                        if in_think:
                            emit("</think>")
                            in_think = False
                        self.wfile.write((json.dumps({"message": {"role": "assistant", "content": ""}, "done": True}) + "\n").encode())
                        self.wfile.flush()
                    except Exception as e:
                        sys.stderr.write(f"[chat_server] stream DONE flush failed: {e}\n")
                    done = True
                    break
                try:
                    j = json.loads(data)
                except Exception as e:
                    sys.stderr.write(f"[chat_server] SSE parse failed: {e}\n")
                    continue
                choices = j.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta", {})
                reasoning_piece = delta.get("reasoning_content") or ""
                content_piece   = delta.get("content") or ""
                if not reasoning_piece and not content_piece:
                    continue
                try:
                    # Reasoning first — open or continue a <think> block.
                    if reasoning_piece:
                        if not in_think:
                            emit("<think>")
                            in_think = True
                        emit(reasoning_piece)
                    # Content after reasoning — close the think block first.
                    if content_piece:
                        if in_think:
                            emit("</think>")
                            in_think = False
                        emit(content_piece)
                except Exception as e:
                    sys.stderr.write(f"[chat_server] stream write failed: {e}\n")
                    return

    def _proxy_passthrough(self, method, target_url, body, is_stream):
        """Straight proxy: request -> response bytes, no translation."""
        req = urllib.request.Request(
            target_url,
            data=body,
            method=method,
            headers={"Content-Type": self.headers.get("Content-Type", "application/json")},
        )
        if "Authorization" in self.headers:
            req.add_header("Authorization", self.headers.get("Authorization"))
        response = urllib.request.urlopen(req, timeout=600)
        self.send_response(response.status)
        for header, value in response.getheaders():
            if header.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(header, value)
        self._cors_headers()
        self.end_headers()
        while True:
            chunk = response.read(4096)
            if not chunk:
                break
            self.wfile.write(chunk)
            if is_stream:
                self.wfile.flush()


class ThreadedHTTPServer(http.server.HTTPServer):
    """Handle each request in a new thread for concurrent streaming."""
    def process_request(self, request, client_address):
        thread = threading.Thread(target=self._handle, args=(request, client_address))
        thread.daemon = True
        thread.start()

    def _handle(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        except Exception:
            self.handle_error(request, client_address)
        finally:
            self.shutdown_request(request)


def open_browser_delayed():
    """Open the browser after a short delay to ensure server is ready."""
    time.sleep(1.0)
    webbrowser.open(f"http://localhost:{CHAT_SERVER_PORT}")


def main():
    ensure_data_dir()
    
    # Try to find the local LAN IP
    local_ip = "127.0.0.1"
    try:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        pass

    print()
    print("=" * 55)
    print("  Portable AI — Chat Server")
    print("=" * 55)
    print()
    print(f"  Local Access:    http://localhost:{CHAT_SERVER_PORT}")
    print(f"  Network Access:  http://{local_ip}:{CHAT_SERVER_PORT}   <-- Use this on phone/other PC!")
    print(f"  Ollama Proxy:       {OLLAMA_HOST}")
    if LLAMACPP_HOST and LLAMACPP_MODEL_ID:
        print(f"  llama.cpp Proxy:    {LLAMACPP_HOST}  (serving '{LLAMACPP_MODEL_ID}')")
    if LLAMA_CPP_MODE:
        print("  Running in LLAMA_CPP_MODE (Translating API requests)")
    print()
    print("  All chats auto-save to the USB drive!")
    print("  Press Ctrl+C to shut down.")
    print()
    print("-" * 55)

    server = ThreadedHTTPServer(("0.0.0.0", CHAT_SERVER_PORT), ChatHandler)

    threading.Thread(target=_chats_flusher, daemon=True).start()
    if "--no-warmup" not in sys.argv:
        threading.Thread(target=_warmup_engines, daemon=True).start()

    # Open browser in background thread
    if "--no-browser" not in sys.argv:
        threading.Thread(target=open_browser_delayed, daemon=True).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Shutting down chat server...")
        server.shutdown()
        print("  Goodbye!")


if __name__ == "__main__":
    main()
