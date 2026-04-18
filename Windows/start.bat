@echo off
setlocal EnableDelayedExpansion
title Eight.ly Stick

set "ROOT=%~dp0.."
set "SHARED=%ROOT%\Shared"
set "STATE=%SHARED%\install-state.json"

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

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$s = Get-Content -Raw '%STATE%' | ConvertFrom-Json; Write-Output $s.backend"`) do set "BACKEND=%%i"
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$s = Get-Content -Raw '%STATE%' | ConvertFrom-Json; Write-Output $s.entrypoint"`) do set "ENTRY=%%i"
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$s = Get-Content -Raw '%STATE%' | ConvertFrom-Json; Write-Output $s.backendLabel"`) do set "BACKEND_LABEL=%%i"
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
    "$s = Get-Content -Raw '%STATE%' | ConvertFrom-Json; Write-Output $s.gpu"`) do set "GPU=%%i"

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

REM Eight.ly Stick uses :11438 so it never collides with a user's existing
REM Ollama install (stock Ollama defaults to :11434, WSL often relays 11434).
set "OLLAMA_MODELS=%SHARED%\models\ollama_data"
set "OLLAMA_HOST=127.0.0.1:11438"
set "OLLAMA_ORIGINS=*"
set "ELY_OLLAMA_URL=http://127.0.0.1:11438"
set "ELY_CHAT_PORT=3333"

curl -s http://127.0.0.1:11438/api/tags >nul 2>&1
if %ERRORLEVEL%==0 (
    echo   [OK] Engine already running on :11438.
    goto :START_CHAT
)

echo   Starting engine on :11438 ...
pushd "%BACKEND_DIR%"
start "" /b "%ENTRY_FULL%" serve
popd

set /a WAIT=0
:WAIT_LOOP
timeout /t 1 /nobreak >nul
curl -s http://127.0.0.1:11438/api/tags >nul 2>&1
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
    "$s = Get-Content -Raw '%STATE%' | ConvertFrom-Json; $m = $s.installed ^| Where-Object { $_.engine -eq 'windows-intel-llamacpp' } ^| Select-Object -First 1; if ($m) { Write-Output ($m.id + '|' + $m.file) }"`) do set "LLAMACPP_SPEC=%%i"

if defined LLAMACPP_SPEC (
    for /f "tokens=1,2 delims=|" %%a in ("%LLAMACPP_SPEC%") do (
        set "LLAMACPP_MODEL_ID=%%a"
        set "LLAMACPP_MODEL_FILE=%%b"
    )
    set "LLAMACPP_DIR=%SHARED%\bin\windows-intel-llamacpp"
    set "LLAMACPP_GGUF=%SHARED%\models\!LLAMACPP_MODEL_FILE!"
    echo.
    echo   Starting secondary engine ^(llama-server SYCL^) on :11441
    echo     model: !LLAMACPP_MODEL_ID!
    pushd "!LLAMACPP_DIR!"
    start "" /b "!LLAMACPP_DIR!\llama-server.exe" -m "!LLAMACPP_GGUF!" -ngl 999 --host 127.0.0.1 --port 11441 --ctx-size 4096 --jinja --reasoning-format none
    popd
    set /a WAIT2=0
    :WAIT_LLAMACPP
    timeout /t 1 /nobreak >nul
    curl -s http://127.0.0.1:11441/health >nul 2>&1
    if !ERRORLEVEL!==0 goto :LLAMACPP_UP
    set /a WAIT2+=1
    if !WAIT2! GEQ 90 (
        echo   WARNING: llama-server did not come up within 90s. Gemma 4 may be unavailable.
        goto :LLAMACPP_SKIP
    )
    goto :WAIT_LLAMACPP
    :LLAMACPP_UP
    echo   [OK] Secondary engine online.
    set "ELY_LLAMACPP_URL=http://127.0.0.1:11441"
    set "ELY_LLAMACPP_MODEL_ID=!LLAMACPP_MODEL_ID!"
    :LLAMACPP_SKIP
)

:START_CHAT
set "PYTHON_CMD="
if exist "%SHARED%\python\python.exe" (
    set "PYTHON_CMD=%SHARED%\python\python.exe"
) else (
    python --version >nul 2>&1
    if !ERRORLEVEL!==0 (
        set "PYTHON_CMD=python"
    ) else (
        echo   Bootstrapping portable Python (11 MB)...
        curl -L --ssl-no-revoke "https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip" -o "%SHARED%\_python.zip"
        if !ERRORLEVEL! NEQ 0 ( echo Python bootstrap download failed. & pause & exit /b 4 )
        powershell -NoProfile -Command "Expand-Archive -Path '%SHARED%\_python.zip' -DestinationPath '%SHARED%\python' -Force"
        del "%SHARED%\_python.zip" >nul 2>&1
        set "PYTHON_CMD=%SHARED%\python\python.exe"
    )
)

echo.
echo   ========================================================
echo      Eight.ly Stick is running.
echo      Chat UI:  http://localhost:3333
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
