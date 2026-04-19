@echo off
setlocal EnableDelayedExpansion
title Eight.ly Forge

REM Ports - override via env before launch if needed
if not defined ELY_RUNTIME_PORT  set "ELY_RUNTIME_PORT=11438"
if not defined ELY_LLAMACPP_PORT set "ELY_LLAMACPP_PORT=11441"
if not defined ELY_CHAT_PORT     set "ELY_CHAT_PORT=3333"
if not defined ELY_INSTALL_PORT  set "ELY_INSTALL_PORT=11439"

set "ROOT=%~dp0.."
set "SHARED=%ROOT%\Shared"
set "STATE=%SHARED%\install-state.json"

REM Kill any orphans from a failed prior install that never tore down the
REM install-time ollama on ELY_INSTALL_PORT.
for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":%ELY_INSTALL_PORT% " ^| findstr "LISTENING"') do (
    taskkill /f /pid %%P >nul 2>&1
)

cls
echo.
echo   ========================================================
echo                      EIGHT.LY STICK
echo   ========================================================
echo.

if not exist "%STATE%" (
    echo   No install detected.
    echo.
    echo   Run Windows\install.bat first to pick your models
    echo   and auto-detect your GPU.
    echo.
    pause
    exit /b 1
)

REM Read all state fields in a single PowerShell call, emitted as SET commands.
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$s = ConvertFrom-Json (Get-Content -Raw '%STATE%'); 'set BACKEND=' + $s.backend; 'set ENTRY=' + $s.entrypoint; 'set BACKEND_LABEL=' + $s.backendLabel; 'set GPU=' + $s.gpu"`) do (%%i)

set "ENTRY_FULL=%ROOT%\%ENTRY%"
set "BACKEND_DIR=%SHARED%\bin\%BACKEND%"

echo   GPU:      %GPU%
echo   Backend:  %BACKEND_LABEL%
echo.

if not exist "%ENTRY_FULL%" (
    echo   ERROR: engine missing at %ENTRY_FULL%
    echo   Re-run install.bat to repair.
    pause
    exit /b 2
)

REM Apply backend-specific env vars from catalog.json
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$c = Get-Content -Raw '%SHARED%\catalog.json' | ConvertFrom-Json; $e = $c.backends.'%BACKEND%'.env; $e.PSObject.Properties | %% { 'set ' + $_.Name + '=' + $_.Value }"`) do (%%i)

REM Eight.ly Forge uses ELY_RUNTIME_PORT (default :11438) so it never collides
REM with a user's existing Ollama install (stock Ollama defaults to :11434,
REM WSL often relays 11434).
set "OLLAMA_MODELS=%SHARED%\models\ollama_data"
set "OLLAMA_HOST=127.0.0.1:%ELY_RUNTIME_PORT%"
set "OLLAMA_ORIGINS=*"
set "ELY_OLLAMA_URL=http://127.0.0.1:%ELY_RUNTIME_PORT%"

curl -s http://127.0.0.1:%ELY_RUNTIME_PORT%/api/tags >nul 2>&1
if %ERRORLEVEL%==0 (
    echo   [OK] Engine already running on :%ELY_RUNTIME_PORT%.
    goto :START_CHAT
)

echo   Starting engine on :%ELY_RUNTIME_PORT% ...
pushd "%BACKEND_DIR%"
start "" /b "%ENTRY_FULL%" serve
popd

set /a WAIT=0
:WAIT_LOOP
timeout /t 1 /nobreak >nul
curl -s http://127.0.0.1:%ELY_RUNTIME_PORT%/api/tags >nul 2>&1
if %ERRORLEVEL%==0 goto :ENGINE_UP
set /a WAIT+=1
if %WAIT% GEQ 30 (
    echo   ERROR: engine did not come up within 30s.
    pause
    exit /b 3
)
goto :WAIT_LOOP

:ENGINE_UP
echo   [OK] Engine online.

REM ---- Start secondary engine (llama-server for Gemma 4 on Arc) if needed ----
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$s = ConvertFrom-Json (Get-Content -Raw '%STATE%'); $m = $null; foreach ($x in $s.installed) { if ($x.engine -eq 'windows-intel-llamacpp') { $m = $x; break } }; if ($m) { Write-Output ($m.id + '~' + $m.file) }"`) do set "LLAMACPP_SPEC=%%i"

if not defined LLAMACPP_SPEC goto :AFTER_LLAMACPP

for /f "tokens=1,2 delims=~" %%a in ("%LLAMACPP_SPEC%") do (
    set "LLAMACPP_MODEL_ID=%%a"
    set "LLAMACPP_MODEL_FILE=%%b"
)
set "LLAMACPP_DIR=%SHARED%\bin\windows-intel-llamacpp"
set "LLAMACPP_GGUF=%SHARED%\models\!LLAMACPP_MODEL_FILE!"
echo.
echo   Starting secondary engine ^(llama-server SYCL^) on :%ELY_LLAMACPP_PORT%
echo     model: !LLAMACPP_MODEL_ID!
pushd "!LLAMACPP_DIR!"
REM llama-server flags tuned for Intel Arc Pro B50 (16 GB VRAM):
REM   --flash-attn on           : fused attention kernels, ~30%% faster + less VRAM
REM   --cache-type-k/v q8_0     : quantize KV cache so we can fit the bigger ctx
REM   --ctx-size 16384          : 4x the prior 4096 ceiling; long reasoning chains fit
REM   --parallel 4              : allow 4 concurrent slots (warms workers, improves throughput)
REM   --batch-size 256 --ubatch-size 32 : optimal batching for Arc Xe-cores
REM   --threads 8 --threads-http 4 : split inference from the HTTP path
REM   --jinja --reasoning-format none : preserve <think> tags inline so the UI collapses them
REM Flags kept on a single line because `^` continuation inside `start ""` with
REM delayed expansion has bitten us before.
start "" /b "!LLAMACPP_DIR!\llama-server.exe" -m "!LLAMACPP_GGUF!" -ngl 999 --host 127.0.0.1 --port %ELY_LLAMACPP_PORT% --ctx-size 16384 --batch-size 256 --ubatch-size 32 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --parallel 4 --threads 8 --threads-http 4 --jinja --reasoning-format none
popd
set /a WAIT2=0
:WAIT_LLAMACPP
timeout /t 1 /nobreak >nul
curl -s http://127.0.0.1:%ELY_LLAMACPP_PORT%/health >nul 2>&1
if !ERRORLEVEL!==0 goto :LLAMACPP_UP
set /a WAIT2+=1
if !WAIT2! GEQ 90 (
    echo   WARNING: llama-server did not come up within 90s. Gemma 4 may be unavailable.
    goto :AFTER_LLAMACPP
)
goto :WAIT_LLAMACPP
:LLAMACPP_UP
echo   [OK] Secondary engine online.
set "ELY_LLAMACPP_URL=http://127.0.0.1:%ELY_LLAMACPP_PORT%"
set "ELY_LLAMACPP_MODEL_ID=!LLAMACPP_MODEL_ID!"
:AFTER_LLAMACPP

:START_CHAT
set "PYTHON_CMD="
if exist "%SHARED%\python\python.exe"                          set "PYTHON_CMD=%SHARED%\python\python.exe"
if not defined PYTHON_CMD if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not defined PYTHON_CMD if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PYTHON_CMD if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if not defined PYTHON_CMD if exist "%LOCALAPPDATA%\Programs\Python\Python310\python.exe" set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not defined PYTHON_CMD (
    for /f "usebackq delims=" %%p in (`where python.exe 2^>nul`) do if not defined PYTHON_CMD set "PYTHON_CMD=%%p"
)
if not defined PYTHON_CMD (
    echo   No Python found. Bootstrapping portable Python ^(11 MB^)...
    curl -L --ssl-no-revoke "https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip" -o "%SHARED%\_python.zip"
    if %ERRORLEVEL% NEQ 0 ( echo   Python bootstrap download failed. & pause & exit /b 4 )
    powershell -NoProfile -Command "Expand-Archive -Path '%SHARED%\_python.zip' -DestinationPath '%SHARED%\python' -Force"
    del "%SHARED%\_python.zip" >nul 2>&1
    if exist "%SHARED%\python\python.exe" set "PYTHON_CMD=%SHARED%\python\python.exe"
)
if not defined PYTHON_CMD (
    echo   ERROR: Could not locate or install Python.
    pause
    exit /b 5
)
echo   Python: %PYTHON_CMD%

echo.
echo   ========================================================
echo      Eight.ly Forge is running.
echo      Chat UI:  http://localhost:%ELY_CHAT_PORT%
echo      Close this window to shut down.
echo   ========================================================
echo.

"%PYTHON_CMD%" "%SHARED%\chat_server.py"

echo.
echo   Shutting down engines...
taskkill /f /im ollama.exe >nul 2>&1
taskkill /f /im ollama-lib.exe >nul 2>&1
taskkill /f /im ollama-windows.exe >nul 2>&1
taskkill /f /im llama-server.exe >nul 2>&1
taskkill /f /im llama-cli.exe >nul 2>&1
echo   Done.
