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
# Eight.ly Forge runs Ollama on :11438 by default. For models whose architecture
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

# Debounced chat save — see _save_chats. Background thread flushes pending
# writes every ELY_SAVE_DEBOUNCE_SECONDS (default 5s) if the in-memory
# version is newer than what's on disk. Stops USB-speed writes from
# dominating streaming latency.
_SAVE_DEBOUNCE_SECONDS = float(os.environ.get("ELY_SAVE_DEBOUNCE_SECONDS", "5"))
_CHATS_LOCK = threading.Lock()
_CHATS_PENDING = {"data": None, "dirty": False, "since": 0.0}


def _chats_flusher():
    """Background thread: persist pending chats at most every N seconds."""
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
                # No indent = 3-4x smaller + faster write. Readable? No.
                # The UI never reads this file directly; it goes through the
                # /api/chats endpoint which re-serializes anyway.
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
            os.replace(tmp, CHATS_FILE)
        except Exception as e:
            sys.stderr.write(f"[chat_server] chat flush failed: {e}\n")


def _warmup_engines():
    """Fire a 1-token dummy chat at each configured engine so the first
    real user message doesn't eat the cold-start latency (typically 3-8s
    on Arc SYCL for Gemma 4 E2B). Runs in a background thread after boot."""
    try:
        time.sleep(2)  # let engines finish binding ports
        payload = json.dumps({
            "messages": [{"role": "user", "content": "hi"}],
            "stream": False,
            "options": {"num_predict": 1}
        }).encode()

        # Warm Ollama (use its real model list - pick first available)
        try:
            req = urllib.request.Request(OLLAMA_HOST + "/api/tags", method="GET")
            tags = json.loads(urllib.request.urlopen(req, timeout=3).read())
            models = [m.get("model") or m.get("name") for m in tags.get("models", [])]
            if models:
                warm = json.dumps({
                    "model": models[0],
                    "messages": [{"role": "user", "content": "hi"}],
                    "stream": False,
                    "options": {"num_predict": 1}
                }).encode()
                r = urllib.request.Request(OLLAMA_HOST + "/api/chat", data=warm,
                                           headers={"Content-Type": "application/json"},
                                           method="POST")
                urllib.request.urlopen(r, timeout=60).read()
                sys.stderr.write(f"[chat_server] warmup: ollama {models[0]} ok\n")
        except Exception as e:
            sys.stderr.write(f"[chat_server] warmup: ollama skipped ({e})\n")

        # Warm llama-server if configured
        if LLAMACPP_HOST and LLAMACPP_MODEL_ID:
            try:
                warm = json.dumps({
                    "model": LLAMACPP_MODEL_ID,
                    "messages": [{"role": "user", "content": "hi"}],
                    "stream": False,
                    "max_tokens": 1
                }).encode()
                r = urllib.request.Request(LLAMACPP_HOST + "/v1/chat/completions",
                                           data=warm,
                                           headers={"Content-Type": "application/json"},
                                           method="POST")
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

        # Document extraction for file drop / paste in the composer.
        elif path == "/api/extract":
            self._extract_document()

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

    # ── Chat Persistence ───────────────────────────────────────
    def _get_chats(self):
        # Prefer the in-memory pending version if the flusher hasn't written
        # yet, so reload-during-stream never shows a stale chat list.
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
        """Stage the chat payload for a debounced write instead of pouring
        several-KB JSON onto the USB drive for every streamed assistant token.

        The FastChatUI POSTs to /api/chats once per message (plus again on
        stream end) with the ENTIRE chats array. On a 500-message history
        that's ~50 KB per write, which is fine on SSD but stalls USB 3.0.
        We accept the body into memory, mark dirty, and the background
        flusher writes at most once per ELY_SAVE_DEBOUNCE_SECONDS (5s)."""
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
        self.wfile.write(json.dumps({"ok": True, "debounced": True}).encode())

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

    # ── Document extract ───────────────────────────────────────
    # POST /api/extract  multipart/form-data  field: "file"
    # -> { name, mime, bytes, pageCount?, words?, text }
    # Shells out per extension. If the extractor binary isn't present,
    # returns a clear error the UI can surface (so the operator knows
    # which apt/choco/brew package to install).
    def _extract_document(self):
        import tempfile, shutil, subprocess, re as _re
        try:
            ct = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in ct.lower():
                self.send_response(400); self._cors_headers(); self.end_headers()
                self.wfile.write(b"expected multipart/form-data"); return
            boundary = None
            for part in ct.split(";"):
                part = part.strip()
                if part.lower().startswith("boundary="):
                    boundary = part.split("=", 1)[1].strip('"')
            if not boundary:
                self.send_response(400); self._cors_headers(); self.end_headers()
                self.wfile.write(b"missing multipart boundary"); return
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0 or length > 50 * 1024 * 1024:
                self.send_response(413); self._cors_headers(); self.end_headers()
                self.wfile.write(b"file too large (50 MB max)"); return
            body = self.rfile.read(length)
            # Minimal multipart parse: find the one file part named "file".
            sep = b"--" + boundary.encode()
            parts = body.split(sep)
            filename = None; mime = ""; payload = b""
            for p in parts:
                if b"Content-Disposition" not in p:
                    continue
                header_block, _, data = p.partition(b"\r\n\r\n")
                hdr = header_block.decode(errors="ignore")
                m = _re.search(r'name="([^"]+)"', hdr)
                fm = _re.search(r'filename="([^"]*)"', hdr)
                if not m or m.group(1) != "file" or not fm:
                    continue
                filename = fm.group(1)
                tm = _re.search(r'Content-Type:\s*([^\r\n]+)', hdr, _re.I)
                if tm: mime = tm.group(1).strip()
                # strip trailing \r\n before next boundary
                if data.endswith(b"\r\n"): data = data[:-2]
                payload = data
                break
            if not filename or not payload:
                self.send_response(400); self._cors_headers(); self.end_headers()
                self.wfile.write(b"no 'file' field in multipart body"); return

            ext = os.path.splitext(filename)[1].lower()
            tmpdir = tempfile.mkdtemp(prefix="forge-extract-")
            tmp_path = os.path.join(tmpdir, os.path.basename(filename) or "upload.bin")
            try:
                with open(tmp_path, "wb") as f: f.write(payload)
                text = ""; page_count = 0
                if ext == ".pdf" or mime == "application/pdf":
                    if shutil.which("pdftotext"):
                        r = subprocess.run(["pdftotext", "-layout", "-nopgbrk", tmp_path, "-"],
                                           capture_output=True, timeout=90)
                        if r.returncode != 0:
                            raise RuntimeError("pdftotext: " + r.stderr.decode(errors="ignore")[:400])
                        text = r.stdout.decode(errors="ignore")
                        if shutil.which("pdfinfo"):
                            r2 = subprocess.run(["pdfinfo", tmp_path], capture_output=True, timeout=15)
                            if r2.returncode == 0:
                                for ln in r2.stdout.decode(errors="ignore").splitlines():
                                    if ln.startswith("Pages:"):
                                        try: page_count = int(ln.split(":", 1)[1].strip()); break
                                        except: pass
                    else:
                        raise RuntimeError("pdftotext not installed (apt install poppler-utils / brew install poppler / choco install xpdf-utils)")
                elif ext == ".docx" or mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
                    if not shutil.which("pandoc"):
                        raise RuntimeError("pandoc not installed (apt/brew/choco install pandoc)")
                    r = subprocess.run(["pandoc", "-f", "docx", "-t", "plain", tmp_path],
                                       capture_output=True, timeout=60)
                    if r.returncode != 0:
                        raise RuntimeError("pandoc: " + r.stderr.decode(errors="ignore")[:400])
                    text = r.stdout.decode(errors="ignore")
                elif ext == ".doc" or mime == "application/msword":
                    if not shutil.which("antiword"):
                        raise RuntimeError("antiword not installed (apt install antiword)")
                    r = subprocess.run(["antiword", tmp_path], capture_output=True, timeout=60)
                    if r.returncode != 0:
                        raise RuntimeError("antiword: " + r.stderr.decode(errors="ignore")[:400])
                    text = r.stdout.decode(errors="ignore")
                elif ext == ".rtf" or mime in ("application/rtf", "text/rtf"):
                    if not shutil.which("pandoc"):
                        raise RuntimeError("pandoc not installed (apt/brew/choco install pandoc)")
                    r = subprocess.run(["pandoc", "-f", "rtf", "-t", "plain", tmp_path],
                                       capture_output=True, timeout=60)
                    if r.returncode != 0:
                        raise RuntimeError("pandoc: " + r.stderr.decode(errors="ignore")[:400])
                    text = r.stdout.decode(errors="ignore")
                else:
                    # Plaintext family: read directly.
                    with open(tmp_path, "rb") as f:
                        raw = f.read()
                    text = raw.decode("utf-8", errors="replace")
                words = sum(1 for _ in _re.finditer(r"\S+", text))
                out = {"name": filename, "mime": mime, "bytes": len(payload),
                       "pageCount": page_count, "words": words, "text": text}
                resp = json.dumps(out).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self._cors_headers(); self.end_headers()
                self.wfile.write(resp)
            finally:
                shutil.rmtree(tmpdir, ignore_errors=True)
        except Exception as e:
            self.send_response(415)
            self.send_header("Content-Type", "text/plain")
            self._cors_headers(); self.end_headers()
            self.wfile.write(("extract failed: " + str(e)).encode())

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

    # Single, authoritative banner. Same format on Windows / Mac / Linux so
    # the URL you open never moves between runs. If an agent dashboard is
    # running it gets a second line; otherwise just the two chat URLs.
    agent_port = os.environ.get("ELY_AGENT_PORT", "").strip()
    agent_url_local = f"http://localhost:{agent_port}" if agent_port else ""
    agent_url_lan   = f"http://{local_ip}:{agent_port}" if agent_port else ""

    print()
    print("=" * 64)
    print("              EIGHT.LY FORGE  -  running")
    print("=" * 64)
    print()
    print("  OPEN IN YOUR BROWSER:")
    print()
    print(f"    On this computer :  http://localhost:{CHAT_SERVER_PORT}")
    print(f"    On phone / LAN   :  http://{local_ip}:{CHAT_SERVER_PORT}")
    if agent_port:
        print()
        print("  AGENT DASHBOARD:")
        print(f"    On this computer :  {agent_url_local}")
        print(f"    On phone / LAN   :  {agent_url_lan}")
    print()
    print(f"  Ollama        :  {OLLAMA_HOST}")
    if LLAMACPP_HOST and LLAMACPP_MODEL_ID:
        print(f"  llama.cpp     :  {LLAMACPP_HOST}  (model: {LLAMACPP_MODEL_ID})")
    print()
    print("  Press Ctrl+C to shut down.")
    print("=" * 64)
    print()

    server = ThreadedHTTPServer(("0.0.0.0", CHAT_SERVER_PORT), ChatHandler)

    # Background: debounced chat-save flusher + engine warm-up.
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
