@echo off
setlocal enabledelayedexpansion
title Portable AI USB - Starting...

REM Define ANSI Colors
for /F %%a in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%a"
set "CYAN=!ESC![36m"
set "GREEN=!ESC![32m"
set "YELLOW=!ESC![33m"
set "RED=!ESC![31m"
set "DIM=!ESC![90m"
set "RESET=!ESC![0m"
set "BOLD=!ESC![1m"

set "USB_ROOT=%~dp0"
set "ROOT_DIR=%USB_ROOT%..\"
set "BIN_DIR=%USB_ROOT%bin"
set "DATA_DIR=%ROOT_DIR%data"
set "ENV_FILE=%DATA_DIR%\ai_settings.env"
set "NODE_DIR=%BIN_DIR%\node-v22.14.0-win-x64"

REM 1. Force the portable AI to save logs/memory strictly to the USB
set "CLAUDE_CONFIG_DIR=%DATA_DIR%\openclaude"
set "XDG_CONFIG_HOME=%DATA_DIR%\config"
set "XDG_DATA_HOME=%DATA_DIR%\app_data"

if not exist "%CLAUDE_CONFIG_DIR%" mkdir "%CLAUDE_CONFIG_DIR%"
if not exist "%XDG_CONFIG_HOME%" mkdir "%XDG_CONFIG_HOME%"
if not exist "%XDG_DATA_HOME%" mkdir "%XDG_DATA_HOME%"

REM Display Banner
echo.
echo !CYAN!    ____            __        __    __        ___    ____!RESET!
echo !CYAN!   / __ \____  ____/ /_____ _/ /_  / /__     /   ^|  /  _/!RESET!
echo !CYAN!  / /_/ / __ \/ __/ __/ __ `/ __ \/ / _ \   / /^| ^|  / /  !RESET!
echo !CYAN! / ____/ /_/ / / / /_/ /_/ / /_/ / /  __/  / ___ ^|_/ /   !RESET!
echo !CYAN!/_/    \____/_/  \__/\__,_/_.___/_/\___/  /_/  ^|_/___/   !RESET!
echo.
echo !CYAN!=========================================================!RESET!
echo   !BOLD!Claude Code - Open Source Multi-Platform!RESET!
echo !CYAN!=========================================================!RESET!
echo.

REM 2. Check if setup was run
if not exist "%NODE_DIR%\node.exe" (
    echo   !RED![ERROR] The portable AI engine was not found!!RESET!
    echo   !YELLOW!Please run 'Setup_First_Time.bat' before starting.!RESET!
    echo.
    pause
    exit /b
)

REM 3. Check for flags (--offline, --quick)
set "SKIP_UPDATE=0"
set "QUICK_MODE=0"
for %%A in (%*) do (
    if /I "%%A"=="--offline" set "SKIP_UPDATE=1"
    if /I "%%A"=="--quick" set "QUICK_MODE=1"
)

if !SKIP_UPDATE!==1 echo   !DIM![~] Offline mode - skipping update check!RESET!
if not !SKIP_UPDATE!==1 (
    echo   !YELLOW![~] Checking for engine updates...!RESET!
    set "PATH=%NODE_DIR%;%PATH%"
    echo   !GREEN![OK] Engine check done!RESET!
)
echo.

REM --------- Boot Local AI Engines (if installed) ---------------------------------------------------
REM If install-core.ps1 has been run, Shared\install-state.json exists.
REM Boot the GPU-accelerated Ollama + optional llama.cpp sidecar + chat UI
REM so the user has both the terminal agent AND a browser chat at :3333.
set "SHARED_DIR=%ROOT_DIR%Shared"
set "LOCAL_STATE=%SHARED_DIR%\install-state.json"
set "LOCAL_ENGINES_UP=0"
if exist "%LOCAL_STATE%" (
    echo   !CYAN![~] Booting local AI engines...!RESET!
    REM start.bat boots Ollama on :11438, llama.cpp on :11441, chat_server on :3333
    start "Local AI Engines" /MIN cmd /c "%USB_ROOT%start.bat"
    set "LOCAL_ENGINES_UP=1"
    timeout /t 5 /nobreak >nul
    echo   !GREEN![OK] Local engines starting - chat UI at http://localhost:3333!RESET!
    echo.
)

REM 4. Check for settings file — NO goto from inside if() blocks
set "SETTINGS_OK=0"
if exist "%ENV_FILE%" findstr /C:"AI_PROVIDER=" "%ENV_FILE%" >nul 2>&1 && set "SETTINGS_OK=1"
if "!SETTINGS_OK!"=="0" if exist "%ENV_FILE%" del "%ENV_FILE%"
if "!SETTINGS_OK!"=="1" goto load_settings

REM ---------------------------------------------------------
REM   PROVIDER SELECTION MENU
REM ---------------------------------------------------------
echo !CYAN!=========================================================!RESET!
echo   !BOLD!AI PROVIDER SELECTION!RESET!
echo !CYAN!=========================================================!RESET!
echo.
echo   !CYAN!1)!RESET! !BOLD!OpenRouter!RESET!   !DIM!- 200+ Free and Paid Models (Recommended)!RESET!
echo   !CYAN!2)!RESET! !BOLD!Gemini!RESET!       !DIM!- Google AI API!RESET!
echo   !CYAN!3)!RESET! !BOLD!Claude!RESET!       !DIM!- Anthropic API!RESET!
echo   !CYAN!4)!RESET! !BOLD!Ollama!RESET!       !DIM!- Local Offline AI!RESET!
echo   !CYAN!5)!RESET! !BOLD!OpenAI!RESET!       !DIM!- GPT / Codex API!RESET!
echo   !CYAN!6)!RESET! !BOLD!NVIDIA NIM!RESET!   !DIM!- Optimized GPU Inference (Free Tier)!RESET!
echo.
:prompt_provider
set "PROVIDER_SEL="
set /p "PROVIDER_SEL=  Select your provider !CYAN!(1-6)!RESET!: "

if "!PROVIDER_SEL!"=="1" goto setup_openrouter
if "!PROVIDER_SEL!"=="2" goto setup_gemini
if "!PROVIDER_SEL!"=="3" goto setup_claude
if "!PROVIDER_SEL!"=="4" goto setup_ollama
if "!PROVIDER_SEL!"=="5" goto setup_openai
if "!PROVIDER_SEL!"=="6" goto setup_nvidia
echo   !RED![ERROR] Invalid selection. Please choose 1-6.!RESET!
goto prompt_provider

REM ---------------------------------------------------------
REM   OPENROUTER SETUP
REM ---------------------------------------------------------
:setup_openrouter
echo.
echo   !CYAN!--- OPENROUTER SETUP ---!RESET!
echo.
set /p "USER_API_KEY=  Enter your OpenRouter API Key: "
    if "!USER_API_KEY!"=="" echo   !RED![ERROR] API Key cannot be empty!!RESET!
    if "!USER_API_KEY!"=="" goto setup_openrouter
REM Mask key for display
set "KEY_MASK=!USER_API_KEY:~0,6!****!USER_API_KEY:~-4!"
echo   !DIM!Key: !KEY_MASK!!RESET!
echo.
echo   !YELLOW![~] Verifying API Key... Please wait...!RESET!
powershell -NoProfile -Command "$headers = @{ 'Authorization' = 'Bearer !USER_API_KEY!' }; try { $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/auth/key' -Headers $headers -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 echo   !RED![ERROR] Invalid or expired OpenRouter API Key!!RESET!
    if errorlevel 1 goto setup_openrouter
echo   !GREEN![OK] Key Verified!!RESET!
echo.
echo   Do you want to use !GREEN!Free!RESET! or !YELLOW!Paid!RESET! models?
echo   !CYAN!1)!RESET! Free Models
echo   !CYAN!2)!RESET! Paid Models
:prompt_tier
set "MODEL_TIER="
set /p "MODEL_TIER=  Select category !CYAN!(1 or 2)!RESET!: "

if "!MODEL_TIER!"=="1" goto setup_free
if "!MODEL_TIER!"=="2" goto setup_paid
echo   !RED![ERROR] Invalid selection. Please choose 1 or 2.!RESET!
goto prompt_tier

:setup_free
echo.
echo   !CYAN!--- FREE MODELS ---!RESET! !DIM!(Live Fetching...)!RESET!
set "idx=1"
for /f "delims=" %%I in ('powershell -NoProfile -Command "$d = (Invoke-RestMethod 'https://openrouter.ai/api/v1/models').data; $free = $d | Where-Object { $_.id -match ':free$' } | Select-Object -First 20 -ExpandProperty id; $free"') do (
    set "FREE_MODEL_!idx!=%%I"
    echo   !CYAN!!idx!^)!RESET! %%I
    set /a "idx+=1"
)
if "!idx!"=="1" (
    echo   !YELLOW![API Error] Could not fetch models, using fallback...!RESET!
    set "FREE_MODEL_1=qwen/qwen-2.5-coder-32b-instruct:free"
    echo   !CYAN!1^)!RESET! qwen/qwen-2.5-coder-32b-instruct:free
    set /a "idx=2"
)
set "FREE_MAX=!idx!"
echo   !CYAN!!FREE_MAX!^)!RESET! !DIM!Custom Free Model...!RESET!
echo.
:prompt_free_sel
set "FREE_SEL="
set /p "FREE_SEL=  Choose a model !CYAN!(1-!FREE_MAX!)!RESET!: "
if defined FREE_SEL (
    if "!FREE_SEL!"=="!FREE_MAX!" (
        set /p "USER_MODEL=  Enter custom model string: "
    ) else (
        for %%V in (!FREE_SEL!) do set "USER_MODEL=!FREE_MODEL_%%V!"
    )
)
    if "!USER_MODEL!"=="" echo   !RED![ERROR] Invalid selection. Please choose 1 to !FREE_MAX!.!RESET!
    if "!USER_MODEL!"=="" goto prompt_free_sel
goto save_settings_openrouter

:setup_paid
echo.
echo   !CYAN!--- PAID MODELS ---!RESET! !DIM!(Live Fetching...)!RESET!
set "idx=1"
for /f "delims=" %%I in ('powershell -NoProfile -Command "$d = (Invoke-RestMethod 'https://openrouter.ai/api/v1/models').data; $paid = $d | Where-Object { $_.id -notmatch ':free$' } | Select-Object -First 20 -ExpandProperty id; $paid"') do (
    set "PAID_MODEL_!idx!=%%I"
    echo   !CYAN!!idx!^)!RESET! %%I
    set /a "idx+=1"
)
if "!idx!"=="1" (
    echo   !YELLOW![API Error] Could not fetch models, using fallback...!RESET!
    set "PAID_MODEL_1=anthropic/claude-3.5-sonnet"
    echo   !CYAN!1^)!RESET! anthropic/claude-3.5-sonnet
    set /a "idx=2"
)
set "PAID_MAX=!idx!"
echo   !CYAN!!PAID_MAX!^)!RESET! !DIM!Custom Paid Model...!RESET!
echo.
:prompt_paid_sel
set "PAID_SEL="
set /p "PAID_SEL=  Choose a model !CYAN!(1-!PAID_MAX!)!RESET!: "
if defined PAID_SEL (
    if "!PAID_SEL!"=="!PAID_MAX!" (
        set /p "USER_MODEL=  Enter custom model string: "
    ) else (
        for %%V in (!PAID_SEL!) do set "USER_MODEL=!PAID_MODEL_%%V!"
    )
)
    if "!USER_MODEL!"=="" echo   !RED![ERROR] Invalid selection. Please choose 1 to !PAID_MAX!.!RESET!
    if "!USER_MODEL!"=="" goto prompt_paid_sel
goto save_settings_openrouter

:save_settings_openrouter
(
    echo # ========================================================
    echo # Portable AI - Master Switchboard 
    echo # ========================================================
    echo AI_PROVIDER=openai
    echo CLAUDE_CODE_USE_OPENAI=1
    echo OPENAI_API_KEY=%USER_API_KEY%
    echo OPENAI_BASE_URL=https://openrouter.ai/api/v1
    echo OPENAI_MODEL=%USER_MODEL%
    echo AI_DISPLAY_MODEL=%USER_MODEL%
) > "%ENV_FILE%"
goto finish_setup

REM ---------------------------------------------------------
REM   NVIDIA NIM SETUP
REM ---------------------------------------------------------
:setup_nvidia
echo.
echo   !CYAN!--- NVIDIA NIM SETUP ---!RESET!
echo.
set /p "USER_API_KEY=  Enter your NVIDIA API Key: "
    if "!USER_API_KEY!"=="" echo   !RED![ERROR] API Key cannot be empty!!RESET!
    if "!USER_API_KEY!"=="" goto setup_nvidia
set "KEY_MASK=!USER_API_KEY:~0,6!****!USER_API_KEY:~-4!"
echo   !DIM!Key: !KEY_MASK!!RESET!
echo.
echo   !YELLOW![~] Verifying API Key... Please wait...!RESET!
powershell -NoProfile -Command "$headers = @{ 'Authorization' = 'Bearer !USER_API_KEY!' }; try { $response = Invoke-RestMethod -Uri 'https://integrate.api.nvidia.com/v1/models' -Headers $headers -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 echo   !RED![ERROR] Invalid or expired NVIDIA API Key!!RESET!
    if errorlevel 1 goto setup_nvidia
echo   !GREEN![OK] Key Verified!!RESET!
echo.
echo   !CYAN!--- NVIDIA MODELS ---!RESET! !DIM!(Live + Curated)!RESET!
set "idx=1"
for %%M in (
    "moonshotai/kimi-k2-instruct" "moonshotai/kimi-k2-thinking" "z-ai/glm4.7"
    "deepseek-ai/deepseek-v3.2" "deepseek-ai/deepseek-v3.1-terminus" "stepfun-ai/step-3.5-flash"
    "mistralai/mistral-large-3-675b-instruct-2512" "qwen/qwen3-coder-480b-a35b-instruct"
    "mistralai/mistral-nemotron" "bytedance/seed-oss-36b-instruct" "mistralai/mamba-codestral-7b-v0.1"
    "google/gemma-7b" "tiiuae/falcon3-7b-instruct" "minimaxai/minimax-m2.7"
) do (
    set "NVIDIA_MODEL_!idx!=%%~M"
    echo   !CYAN!!idx!^)!RESET! %%~M
    set /a "idx+=1"
)
for /f "delims=" %%I in ('powershell -NoProfile -Command "$headers = @{ 'Authorization' = 'Bearer !USER_API_KEY!' }; try { $d = (Invoke-RestMethod -Uri 'https://integrate.api.nvidia.com/v1/models' -Headers $headers).data; $d | Select-Object -ExpandProperty id | Select-Object -First 15 } catch { }"') do (
    set "EXISTS=0"
    for /L %%K in (1,1,14) do (
        if "%%I"=="!NVIDIA_MODEL_%%K!" set "EXISTS=1"
    )
    if !EXISTS!==0 (
        set "NVIDIA_MODEL_!idx!=%%I"
        echo   !CYAN!!idx!^)!RESET! %%I
        set /a "idx+=1"
    )
)
if "!idx!"=="1" (
    echo   !YELLOW![API Error] Could not fetch models, using fallback...!RESET!
    set "NVIDIA_MODEL_1=meta/llama-3.1-70b-instruct"
    echo   !CYAN!1^)!RESET! meta/llama-3.1-70b-instruct
    set /a "idx=2"
)
set "MAX_IDX=!idx!"
echo   !CYAN!!MAX_IDX!^)!RESET! !DIM!Custom NVIDIA Model...!RESET!
echo.
:prompt_nvidia_sel
set "MODEL_SEL="
set /p "MODEL_SEL=  Choose a model !CYAN!(1-!MAX_IDX!)!RESET!: "
if defined MODEL_SEL (
    if "!MODEL_SEL!"=="!MAX_IDX!" (
        set /p "USER_MODEL=  Enter custom model string: "
    ) else (
        for %%V in (!MODEL_SEL!) do set "USER_MODEL=!NVIDIA_MODEL_%%V!"
    )
)
    if "!USER_MODEL!"=="" echo   !RED![ERROR] Invalid selection. Please choose 1 to !MAX_IDX!.!RESET!
    if "!USER_MODEL!"=="" goto prompt_nvidia_sel

:save_settings_nvidia
(
    echo AI_PROVIDER=openai
    echo CLAUDE_CODE_USE_OPENAI=1
    echo OPENAI_API_KEY=%USER_API_KEY%
    echo OPENAI_BASE_URL=https://integrate.api.nvidia.com/v1
    echo OPENAI_MODEL=%USER_MODEL%
    echo AI_DISPLAY_MODEL=%USER_MODEL%
) > "%ENV_FILE%"
goto finish_setup

REM ---------------------------------------------------------
REM   GEMINI SETUP
REM ---------------------------------------------------------
:setup_gemini
echo.
echo   !CYAN!--- GEMINI SETUP ---!RESET!
echo.
set /p "USER_API_KEY=  Enter your Gemini API Key: "
    if "!USER_API_KEY!"=="" echo   !RED![ERROR] API Key cannot be empty!!RESET!
    if "!USER_API_KEY!"=="" goto setup_gemini
set "KEY_MASK=!USER_API_KEY:~0,6!****!USER_API_KEY:~-4!"
echo   !DIM!Key: !KEY_MASK!!RESET!
echo.
echo   !YELLOW![~] Verifying API Key... Please wait...!RESET!
powershell -NoProfile -Command "try { $response = Invoke-RestMethod -Uri 'https://generativelanguage.googleapis.com/v1beta/models?key=!USER_API_KEY!' -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 echo   !RED![ERROR] Invalid or expired Gemini API Key!!RESET!
    if errorlevel 1 goto setup_gemini
echo   !GREEN![OK] Key Verified!!RESET!
echo.
set /p "USER_MODEL=  Enter Model !DIM!(Enter for gemini-2.0-pro-exp-02-05)!RESET!: "
if "%USER_MODEL%"=="" set "USER_MODEL=gemini-2.0-pro-exp-02-05"
(
    echo AI_PROVIDER=gemini
    echo GEMINI_API_KEY=%USER_API_KEY%
    echo AI_DISPLAY_MODEL=%USER_MODEL%
) > "%ENV_FILE%"
goto finish_setup

REM ---------------------------------------------------------
REM   CLAUDE SETUP
REM ---------------------------------------------------------
:setup_claude
echo.
echo   !CYAN!--- CLAUDE SETUP ---!RESET!
echo.
set /p "USER_API_KEY=  Enter your Anthropic API Key: "
    if "!USER_API_KEY!"=="" echo   !RED![ERROR] API Key cannot be empty!!RESET!
    if "!USER_API_KEY!"=="" goto setup_claude
set "KEY_MASK=!USER_API_KEY:~0,6!****!USER_API_KEY:~-4!"
echo   !DIM!Key: !KEY_MASK!!RESET!
echo.
echo   !YELLOW![~] Verifying API Key... Please wait...!RESET!
powershell -NoProfile -Command "$headers = @{ 'x-api-key' = '!USER_API_KEY!'; 'anthropic-version' = '2023-06-01' }; try { $response = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/models' -Headers $headers -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 echo   !RED![ERROR] Invalid or expired Anthropic API Key!!RESET!
    if errorlevel 1 goto setup_claude
echo   !GREEN![OK] Key Verified!!RESET!
echo.
set /p "USER_MODEL=  Enter Model !DIM!(Enter for claude-3-7-sonnet-20250219)!RESET!: "
if "%USER_MODEL%"=="" set "USER_MODEL=claude-3-7-sonnet-20250219"
(
    echo AI_PROVIDER=anthropic
    echo ANTHROPIC_API_KEY=%USER_API_KEY%
    echo AI_DISPLAY_MODEL=%USER_MODEL%
) > "%ENV_FILE%"
goto finish_setup

REM ---------------------------------------------------------
REM   OLLAMA SETUP
REM ---------------------------------------------------------
:setup_ollama
echo.
echo   !CYAN!--- OLLAMA LOCAL SETUP ---!RESET!
echo.
REM If our local GPU-accelerated engine is installed, use it on :11438.
REM Otherwise fall back to the stock Ollama on :11434.
set "OLLAMA_PORT=11434"
if exist "%LOCAL_STATE%" (
    set "OLLAMA_PORT=11438"
    echo   !GREEN![INFO] Using GPU-accelerated local engine on :11438!RESET!
    REM List installed models from install-state.json
    echo.
    echo   !BOLD!Installed local models:!RESET!
    powershell -NoProfile -Command "$s = ConvertFrom-Json (Get-Content -Raw '%LOCAL_STATE%'); foreach ($m in $s.installed) { Write-Host ('    - ' + $m.name + ' (' + $m.id + ')') }"
    echo.
)
set /p "USER_MODEL=  Enter local model !DIM!(Enter for gemma2-2b)!RESET!: "
if "%USER_MODEL%"=="" set "USER_MODEL=gemma2-2b"
(
    echo AI_PROVIDER=ollama
    echo CLAUDE_CODE_USE_OPENAI=1
    echo OPENAI_API_KEY=ollama
    echo OPENAI_BASE_URL=http://localhost:!OLLAMA_PORT!/v1
    echo OPENAI_MODEL=%USER_MODEL%
    echo AI_DISPLAY_MODEL=%USER_MODEL%
) > "%ENV_FILE%"
goto finish_setup

REM ---------------------------------------------------------
REM   OPENAI SETUP
REM ---------------------------------------------------------
:setup_openai
echo.
echo   !CYAN!--- OPENAI / CODEX SETUP ---!RESET!
echo.
set /p "USER_API_KEY=  Enter your OpenAI API Key: "
    if "!USER_API_KEY!"=="" echo   !RED![ERROR] API Key cannot be empty!!RESET!
    if "!USER_API_KEY!"=="" goto setup_openai
set "KEY_MASK=!USER_API_KEY:~0,6!****!USER_API_KEY:~-4!"
echo   !DIM!Key: !KEY_MASK!!RESET!
echo.
echo   !YELLOW![~] Verifying API Key... Please wait...!RESET!
powershell -NoProfile -Command "$headers = @{ 'Authorization' = 'Bearer !USER_API_KEY!' }; try { $response = Invoke-RestMethod -Uri 'https://api.openai.com/v1/models' -Headers $headers -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 echo   !RED![ERROR] Invalid or expired OpenAI API Key!!RESET!
    if errorlevel 1 goto setup_openai
echo   !GREEN![OK] Key Verified!!RESET!
echo.
set /p "USER_MODEL=  Enter Model !DIM!(Enter for gpt-4o)!RESET!: "
if "%USER_MODEL%"=="" set "USER_MODEL=gpt-4o"
(
    echo AI_PROVIDER=openai
    echo CLAUDE_CODE_USE_OPENAI=1
    echo OPENAI_API_KEY=%USER_API_KEY%
    echo OPENAI_BASE_URL=https://api.openai.com/v1
    echo OPENAI_MODEL=%USER_MODEL%
    echo AI_DISPLAY_MODEL=%USER_MODEL%
) > "%ENV_FILE%"
goto finish_setup

:finish_setup
echo.
echo   !GREEN![OK] Settings saved!!RESET!
echo.

REM ---------------------------------------------------------
REM   LOAD SETTINGS + WELCOME BACK SCREEN
REM ---------------------------------------------------------
:load_settings
REM Load the settings from ai_settings.env
for /f "usebackq tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    set "%%A=%%~B"
)

if not "!AI_PROVIDER!"=="anthropic" (
    set "ANTHROPIC_API_KEY="
)

REM Friendly provider name
set "PROVIDER_NAME=!AI_PROVIDER!"
if "!AI_PROVIDER!"=="openai" (
    if defined OPENAI_BASE_URL (
        echo !OPENAI_BASE_URL! | findstr /C:"openrouter" >nul && set "PROVIDER_NAME=OpenRouter"
        echo !OPENAI_BASE_URL! | findstr /C:"integrate.api.nvidia.com" >nul && set "PROVIDER_NAME=NVIDIA NIM"
        echo !OPENAI_BASE_URL! | findstr /C:"api.openai.com" >nul && set "PROVIDER_NAME=OpenAI"
        echo !OPENAI_BASE_URL! | findstr /C:"localhost:11434" >nul && set "PROVIDER_NAME=Ollama"
    )
)
if "!AI_PROVIDER!"=="gemini" set "PROVIDER_NAME=Google Gemini"
if "!AI_PROVIDER!"=="anthropic" set "PROVIDER_NAME=Anthropic Claude"
if "!AI_PROVIDER!"=="ollama" set "PROVIDER_NAME=Ollama (Local)"

title Portable AI USB - !PROVIDER_NAME! - !AI_DISPLAY_MODEL!

echo !CYAN!=========================================================!RESET!
echo   !BOLD!Claude Code - Ready (Multi-Platform)!RESET!
echo !CYAN!=========================================================!RESET!
echo.
echo   !BOLD!Provider!RESET! : !GREEN!!PROVIDER_NAME!!RESET!
echo   !BOLD!Model!RESET!    : !GREEN!!AI_DISPLAY_MODEL!!RESET!
echo   !BOLD!Data!RESET!     : !DIM!Portable Mode (No PC Leaks)!RESET!
if "%LOCAL_ENGINES_UP%"=="1" echo.
if "%LOCAL_ENGINES_UP%"=="1" echo   Chat UI  : http://localhost:3333  (uncensored local models)
if "%LOCAL_ENGINES_UP%"=="1" echo   Dashboard: http://localhost:3000  (OpenClaude web UI)
echo.
echo !CYAN!=========================================================!RESET!
echo.

REM Auto-open the chat UI in the default browser so the user sees something immediately
if "%LOCAL_ENGINES_UP%"=="1" start "" http://localhost:3333

:prompt_launch_mode
REM Quick mode: skip menu, go straight to limitless
if !QUICK_MODE!==1 echo   !RED!!BOLD!QUICK LAUNCH - Limitless Mode!RESET!
if !QUICK_MODE!==1 goto launch_limitless
echo   !BOLD!Select Launch Mode:!RESET!
echo   !CYAN!1)!RESET! !GREEN!Normal Mode!RESET!    !DIM!- Confirms before running commands!RESET!
echo   !CYAN!2)!RESET! !RED!Limitless Mode!RESET! !DIM!- Auto-executes everything (Advanced)!RESET!
echo.
set "LAUNCH_MODE="
set /p "LAUNCH_MODE=  Select mode !CYAN!(1 or 2)!RESET!: "

if "!LAUNCH_MODE!"=="1" goto launch_normal
if "!LAUNCH_MODE!"=="2" goto launch_limitless
echo   !RED![ERROR] Invalid selection.!RESET!
goto prompt_launch_mode

:launch_limitless
echo.
echo   !RED!!BOLD![!] LIMITLESS MODE ACTIVATED!RESET!
set "CMD_ARGS=--dangerously-skip-permissions"
goto do_launch

:launch_normal
echo.
echo   !GREEN![OK] Normal mode selected.!RESET!
set "CMD_ARGS="
goto do_launch

:do_launch
if "!AI_PROVIDER!"=="ollama" (
    if exist "%DATA_DIR%\ollama\ollama.exe" (
        echo   !CYAN![~] Starting Local Ollama Server...!RESET!
        set "OLLAMA_MODELS=%DATA_DIR%\ollama\data"
        start "Ollama Portable" /B /MIN "%DATA_DIR%\ollama\ollama.exe" serve >nul 2>&1
        timeout /t 3 /nobreak >nul
        echo   !GREEN![OK] Ollama running!RESET!
        echo.
    )
)

echo   !CYAN![~] Starting AI Engine...!RESET!
echo.
set "PATH=%NODE_DIR%;%PATH%"
if exist "%BIN_DIR%\python\python.exe" set "PATH=%BIN_DIR%\python;%BIN_DIR%\python\Scripts;%PATH%"
if exist "%BIN_DIR%\git\cmd\git.exe" set "PATH=%BIN_DIR%\git\cmd;%PATH%"

set "PROVIDER_ARGS="
if defined AI_PROVIDER set "PROVIDER_ARGS=--provider !AI_PROVIDER!"

pushd "%BIN_DIR%"
call npx.cmd openclaude !PROVIDER_ARGS! !CMD_ARGS!
popd

if "!AI_PROVIDER!"=="ollama" (
    if exist "%DATA_DIR%\ollama\ollama.exe" (
        echo.
        echo   !CYAN![~] Stopping Local Ollama Server...!RESET!
        taskkill /F /IM ollama.exe >nul 2>&1
    )
)

pause