@echo off
setlocal enabledelayedexpansion
title Portable AI USB - First Time Setup

:: Define ANSI Colors
for /F %%a in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%a"
set "CYAN=!ESC![36m"
set "GREEN=!ESC![32m"
set "YELLOW=!ESC![33m"
set "RED=!ESC![31m"
set "MAGENTA=!ESC![35m"
set "DIM=!ESC![90m"
set "RESET=!ESC![0m"
set "BOLD=!ESC![1m"

echo.
echo !CYAN!    ____            __        __    __        ___    ____!RESET!
echo !CYAN!   / __ \____  ____/ /_____ _/ /_  / /__     /   ^|  /  _/!RESET!
echo !CYAN!  / /_/ / __ \/ __/ __/ __ `/ __ \/ / _ \   / /^| ^|  / /  !RESET!
echo !CYAN! / ____/ /_/ / / / /_/ /_/ / /_/ / /  __/  / ___ ^|_/ /   !RESET!
echo !CYAN!/_/    \____/_/  \__/\__,_/_.___/_/\___/  /_/  ^|_/___/   !RESET!
echo.
echo !CYAN!=========================================================!RESET!
echo   !BOLD!Claude Code - Open Source Setup!RESET!
echo !CYAN!=========================================================!RESET!
echo.
echo   This will download the AI Engine and Core Files
echo   directly to this folder so it can run entirely offline.
echo.

:: ─── Step 0: Internet Connectivity Check ─────────────────────
echo   !YELLOW![~] Checking internet connectivity...!RESET!
curl.exe -s -o nul -w "" --connect-timeout 5 https://nodejs.org >nul 2>&1
if errorlevel 1 (
    echo   !RED![ERROR] No internet connection detected!!RESET!
    echo.
    echo   This setup requires internet to download components.
    echo   Please connect to WiFi or Ethernet and try again.
    echo.
    pause
    exit /b
)
echo   !GREEN![OK] Internet connection verified!!RESET!
echo.

:: ─── Step 1: Disk Space Check ────────────────────────────────
set "USB_ROOT=%~dp0"
set "ROOT_DIR=%USB_ROOT%..\"
set "BIN_DIR=%USB_ROOT%bin"
set "DATA_DIR=%ROOT_DIR%data"

echo   !YELLOW![~] Checking available disk space...!RESET!
set "DRIVE_LETTER=%USB_ROOT:~0,1%"
set "FREE_MB=0"
for /f "tokens=*" %%M in ('powershell -NoProfile -Command "[math]::Floor((Get-PSDrive '!DRIVE_LETTER!').Free / 1MB)"') do set "FREE_MB=%%M"
if !FREE_MB! LSS 150 (
    echo   !RED![ERROR] Not enough disk space!!RESET!
    echo   Available: !FREE_MB! MB  ^|  Required: ~150 MB
    echo.
    pause
    exit /b
)
echo   !GREEN![OK] Disk space OK: !FREE_MB! MB available!RESET!
echo.

:: ─── Step 2: Tools Diagnostic ────────────────────────────────
set "HAS_GIT=0"
set "HAS_PYTHON=0"
where git >nul 2>&1
if not errorlevel 1 set "HAS_GIT=1"
where python >nul 2>&1
if not errorlevel 1 set "HAS_PYTHON=1"

echo   !YELLOW![DIAGNOSTIC] Host PC Pre-Check:!RESET!
if "!HAS_GIT!"=="1" ( echo   - Git:    !GREEN![FOUND]!RESET! ) else ( echo   - Git:    !RED![MISSING]!RESET! )
if "!HAS_PYTHON!"=="1" ( echo   - Python: !GREEN![FOUND]!RESET! ) else ( echo   - Python: !RED![MISSING]!RESET! )
echo.
if "!HAS_GIT!"=="1" if "!HAS_PYTHON!"=="1" (
    echo   !DIM![INFO] Git and Python are already installed on your PC.!RESET!
    echo   !DIM!However, installing them on the USB makes it fully portable!RESET!
    echo   !DIM!for PCs that don't have them.!RESET!
) else (
    echo   Would you like to install Portable Python and Git inside the USB?
    echo   ^(Adds ~70MB but guarantees the AI can write/run code on ANY computer^)
)
:prompt_tools
set "PACK_TOOLS="
set /p "PACK_TOOLS=  Install Portable Developer Tools? (Y/N): "
if defined PACK_TOOLS set "PACK_TOOLS=!PACK_TOOLS: =!"
if /I "!PACK_TOOLS!"=="N" goto skip_tools_prompt
if /I "!PACK_TOOLS!"=="Y" goto skip_tools_prompt
echo   !RED![ERROR] Please select Y or N.!RESET!
goto prompt_tools

:skip_tools_prompt
echo.

:: ─── Variables ───────────────────────────────────────────────
set "NODE_ZIP=node-v22.14.0-win-x64.zip"
set "NODE_URL=https://nodejs.org/dist/v22.14.0/%NODE_ZIP%"
set "NODE_DIR=%BIN_DIR%\node-v22.14.0-win-x64"
set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/MinGit-2.44.0-64-bit.zip"
set "PYTHON_URL=https://www.python.org/ftp/python/3.12.3/python-3.12.3-embed-amd64.zip"
set "STEP=1"
set "TOTAL_STEPS=3"
if /I "!PACK_TOOLS!"=="Y" set "TOTAL_STEPS=4"

if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"

echo !CYAN!---------------------------------------------------------!RESET!
echo   !BOLD!Starting Installation...!RESET!
echo !CYAN!---------------------------------------------------------!RESET!
echo.

:: ─── Step 3: Download Node.js ────────────────────────────────
if exist "%NODE_DIR%\npm.cmd" (
    echo   !GREEN![!STEP!/!TOTAL_STEPS!] Portable Node.js ... already installed [SKIP]!RESET!
) else (
    echo   !CYAN![!STEP!/!TOTAL_STEPS!] Downloading Portable Node.js ^(~30MB^)...!RESET!

    :: Download with retry (up to 3 attempts)
    set "DL_OK=0"
    for /L %%R in (1,1,3) do (
        if !DL_OK!==0 (
            if %%R GTR 1 echo   !YELLOW!  [~] Retry attempt %%R/3...!RESET!
            curl.exe -# -L -o "%BIN_DIR%\%NODE_ZIP%" "%NODE_URL%"
            if not errorlevel 1 set "DL_OK=1"
        )
    )
    if !DL_OK!==0 (
        echo   !RED![FATAL] Failed to download Node.js after 3 attempts!!RESET!
        echo   !RED!Please check your internet connection and try again.!RESET!
        pause
        exit /b
    )

    echo   !CYAN!  Extracting...!RESET!
    tar.exe -xf "%BIN_DIR%\%NODE_ZIP%" -C "%BIN_DIR%"
    del "%BIN_DIR%\%NODE_ZIP%" 2>nul

    :: Verify extraction
    if not exist "%NODE_DIR%\npm.cmd" (
        echo   !RED![FATAL] Extraction failed! node/npm not found.!RESET!
        echo   !RED!Please delete the bin folder and try again.!RESET!
        pause
        exit /b
    )
    echo   !GREEN!  [OK] Node.js installed successfully!!RESET!
)
set /a "STEP+=1"
echo.

:: ─── Step 4: Install OpenClaude ──────────────────────────────
echo   !CYAN![!STEP!/!TOTAL_STEPS!] Installing OpenClaude Engine...!RESET!

pushd "%BIN_DIR%"
:: Add Node to PATH so postinstall scripts can find it
set "PATH=%NODE_DIR%;%PATH%"
:: Skip npm init if package.json already exists
if not exist "%BIN_DIR%\package.json" (
    call npm init -y >nul 2>&1
)
call npm install @gitlawb/openclaude --no-audit --no-fund --loglevel=error
if errorlevel 1 (
    echo   !RED![FATAL] OpenClaude installation failed!!RESET!
    popd
    pause
    exit /b
)
popd
echo   !GREEN!  [OK] OpenClaude engine installed!!RESET!
set /a "STEP+=1"
echo.

:: ─── Step 5: Install Portable Dev Tools ──────────────────────
if /I "!PACK_TOOLS!"=="Y" (
    echo   !CYAN![!STEP!/!TOTAL_STEPS!] Installing Portable Developer Tools...!RESET!
    echo.

    :: ── Git ──────────────────────────────────────────────────
    if not exist "%BIN_DIR%\git" (
        echo   !YELLOW!  [a] Downloading MinGit ^(Portable Git^)...!RESET!
        set "DL_OK=0"
        for /L %%R in (1,1,3) do (
            if !DL_OK!==0 (
                if %%R GTR 1 echo   !YELLOW!      Retry %%R/3...!RESET!
                curl.exe -# -L -o "%BIN_DIR%\mingit.zip" "%GIT_URL%"
                if not errorlevel 1 set "DL_OK=1"
            )
        )
        if !DL_OK!==0 (
            echo   !RED!  [WARN] Git download failed - skipping.!RESET!
        ) else (
            echo   !DIM!      Extracting...!RESET!
            if not exist "%BIN_DIR%\git" mkdir "%BIN_DIR%\git"
            tar.exe -xf "%BIN_DIR%\mingit.zip" -C "%BIN_DIR%\git"
            del "%BIN_DIR%\mingit.zip" 2>nul
            echo   !GREEN!  [OK] Portable Git installed!!RESET!
        )
    ) else (
        echo   !GREEN!  [a] Portable Git ... already installed [SKIP]!RESET!
    )
    echo.

    :: ── Python ───────────────────────────────────────────────
    if not exist "%BIN_DIR%\python" (
        echo   !YELLOW!  [b] Downloading Portable Python...!RESET!
        set "DL_OK=0"
        for /L %%R in (1,1,3) do (
            if !DL_OK!==0 (
                if %%R GTR 1 echo   !YELLOW!      Retry %%R/3...!RESET!
                curl.exe -# -L -o "%BIN_DIR%\python.zip" "%PYTHON_URL%"
                if not errorlevel 1 set "DL_OK=1"
            )
        )
        if !DL_OK!==0 (
            echo   !RED!  [WARN] Python download failed - skipping.!RESET!
        ) else (
            echo   !DIM!      Extracting...!RESET!
            if not exist "%BIN_DIR%\python" mkdir "%BIN_DIR%\python"
            tar.exe -xf "%BIN_DIR%\python.zip" -C "%BIN_DIR%\python"
            del "%BIN_DIR%\python.zip" 2>nul
            echo   !GREEN!  [OK] Portable Python installed!!RESET!
        )
    ) else (
        echo   !GREEN!  [b] Portable Python ... already installed [SKIP]!RESET!
    )
    echo.
)

:: ─── Step 6: Local AI Models (GPU-accelerated uncensored chat) ────
echo.
echo !CYAN!---------------------------------------------------------!RESET!
echo   !BOLD!Local AI Setup (GPU-accelerated uncensored models)!RESET!
echo !CYAN!---------------------------------------------------------!RESET!
echo.
echo   This installs a local GPU-accelerated AI engine (Ollama) and
echo   curated uncensored models directly on the stick. These power
echo   the chat UI at http://localhost:3333 - completely offline,
echo   completely private.
echo.
:prompt_local
set "INSTALL_LOCAL="
set /p "INSTALL_LOCAL=  Install local AI models? (Y/N): "
if defined INSTALL_LOCAL set "INSTALL_LOCAL=!INSTALL_LOCAL: =!"
if /I "!INSTALL_LOCAL!"=="Y" (
    echo.
    echo   !CYAN![~] Running local model installer...!RESET!
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%USB_ROOT%install-core.ps1"
    echo.
) else if /I "!INSTALL_LOCAL!"=="N" (
    echo.
    echo   !DIM!Skipped local models. You can install them later by!RESET!
    echo   !DIM!running Windows\install.bat or from the chat UI Models button.!RESET!
    echo.
) else (
    echo   !RED![ERROR] Please select Y or N.!RESET!
    goto prompt_local
)

:: ─── Step 7: Portable VS Code (optional) ────────────────────
echo.
echo !CYAN!---------------------------------------------------------!RESET!
echo   !BOLD!Portable VS Code (optional)!RESET!
echo !CYAN!---------------------------------------------------------!RESET!
echo.
echo   VS Code Portable runs from the stick with OpenClaude pre-configured
echo   as the AI coding assistant inside the editor. Your extensions and
echo   settings travel with the stick across computers.
echo.
set "VSCODE_DIR=%ROOT_DIR%tools\vscode"
if exist "%VSCODE_DIR%\Code.exe" (
    echo   !GREEN![OK] VS Code Portable already installed.!RESET!
    echo.
    goto skip_vscode
)
:prompt_vscode
set "INSTALL_VSCODE="
set /p "INSTALL_VSCODE=  Install Portable VS Code? (~120MB download) (Y/N): "
if defined INSTALL_VSCODE set "INSTALL_VSCODE=!INSTALL_VSCODE: =!"
if /I "!INSTALL_VSCODE!"=="Y" goto do_vscode
goto after_vscode
:do_vscode
echo.
echo   !CYAN![~] Downloading VS Code Portable...!RESET!
if not exist "%ROOT_DIR%tools" mkdir "%ROOT_DIR%tools"
set "VSCODE_ZIP=%ROOT_DIR%tools\_vscode.zip"
set "VSCODE_URL=https://update.code.visualstudio.com/latest/win32-x64-archive/stable"
set "DL_OK=0"
for /L %%R in (1,1,3) do (
    if !DL_OK!==0 (
        if %%R GTR 1 echo   !YELLOW!  Retry %%R/3...!RESET!
        curl.exe -# -L -o "!VSCODE_ZIP!" "!VSCODE_URL!"
        if not errorlevel 1 set "DL_OK=1"
    )
)
if !DL_OK!==0 (
    echo   !RED!  [WARN] VS Code download failed. Skipping.!RESET!
    goto after_vscode
)
echo   !CYAN!  Extracting (this takes a minute)...!RESET!
if not exist "!VSCODE_DIR!" mkdir "!VSCODE_DIR!"
REM Use PowerShell Expand-Archive instead of tar.exe — more reliable on Windows for large ZIPs
powershell -NoProfile -Command "Expand-Archive -Path '!VSCODE_ZIP!' -DestinationPath '!VSCODE_DIR!' -Force"
if errorlevel 1 (
    echo   !RED!  [WARN] VS Code extraction failed. Skipping.!RESET!
    goto after_vscode
)
del "!VSCODE_ZIP!" 2>nul
REM Enable portable mode by creating the data folder
if not exist "!VSCODE_DIR!\data" mkdir "!VSCODE_DIR!\data"
if not exist "!VSCODE_DIR!\data\user-data" mkdir "!VSCODE_DIR!\data\user-data"
echo   !GREEN!  [OK] VS Code Portable installed!!RESET!
echo   !DIM!  Portable mode enabled (data\user-data on the stick).!RESET!
echo.
goto after_vscode_done

:after_vscode
if /I "!INSTALL_VSCODE!"=="N" (
    echo.
    echo   !DIM!Skipped VS Code. You can install it manually later.!RESET!
    echo.
)
:after_vscode_done else if /I "!INSTALL_VSCODE!"=="N" (
    echo.
    echo   !DIM!Skipped VS Code. You can install it manually later.!RESET!
    echo.
) else (
    echo   !RED![ERROR] Please select Y or N.!RESET!
    goto prompt_vscode
)
:skip_vscode

:: ─── Step 8: Extensions + Coding CLIs ───────────────────────
echo.
echo !CYAN!---------------------------------------------------------!RESET!
echo   !BOLD!Installing Extensions + Coding Tools!RESET!
echo !CYAN!---------------------------------------------------------!RESET!
echo.
echo   Installing VS Code extensions (Continue, Cline, Claude Code,
echo   Python, GitLens, Prettier, ESLint) and coding CLIs (Codex,
echo   Claude Code CLI, Aider). All pre-configured for your stick.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%USB_ROOT%install-extensions.ps1"

:: ─── Installation Summary ────────────────────────────────────

:: Get installed OpenClaude version
set "OC_VERSION=unknown"
if exist "%BIN_DIR%\node_modules\@gitlawb\openclaude\package.json" (
    for /f "tokens=2 delims=:," %%V in ('findstr /C:"\"version\"" "%BIN_DIR%\node_modules\@gitlawb\openclaude\package.json"') do (
        set "OC_VERSION=%%~V"
        set "OC_VERSION=!OC_VERSION: =!"
    )
)

:: Get Node version
set "NODE_VERSION=unknown"
if exist "%NODE_DIR%\node.exe" (
    for /f "tokens=*" %%V in ('"%NODE_DIR%\node.exe" -v 2^>nul') do set "NODE_VERSION=%%V"
)

:: Calculate bin folder size
set "BIN_SIZE=0"
for /f "tokens=*" %%S in ('powershell -NoProfile -Command "[math]::Round((Get-ChildItem -Recurse '%BIN_DIR%' -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)" 2^>nul') do set "BIN_SIZE=%%S"

echo.
echo !CYAN!=========================================================!RESET!
echo   !GREEN!!BOLD![DONE] Setup Complete!!RESET!
echo !CYAN!=========================================================!RESET!
echo.
echo   !BOLD!Installation Summary:!RESET!
echo   !CYAN!-------------------------------------------------!RESET!
echo   Node.js      : !GREEN!!NODE_VERSION!!RESET!
echo   OpenClaude   : !GREEN!v!OC_VERSION!!RESET!
if exist "%BIN_DIR%\git\cmd\git.exe" (
    echo   Portable Git : !GREEN![INSTALLED]!RESET!
) else (
    echo   Portable Git : !DIM![NOT INSTALLED]!RESET!
)
if exist "%BIN_DIR%\python\python.exe" (
    echo   Portable Py  : !GREEN![INSTALLED]!RESET!
) else (
    echo   Portable Py  : !DIM![NOT INSTALLED]!RESET!
)
echo   !CYAN!-------------------------------------------------!RESET!
echo   Total Size   : !YELLOW!!BIN_SIZE! MB!RESET!
echo   Location     : !DIM!!BIN_DIR!!RESET!
echo.
echo   !DIM!You never have to run this again unless you!RESET!
echo   !DIM!delete the bin folder.!RESET!
echo.

goto prompt_launch

:: ─── Auto-Launch Prompt ──────────────────────────────────────
:prompt_launch
set "LAUNCH_NOW="
set /p "LAUNCH_NOW=  !BOLD!Launch Start_AI.bat now? (Y/N): !RESET!"
if defined LAUNCH_NOW set "LAUNCH_NOW=!LAUNCH_NOW: =!"
if /I "!LAUNCH_NOW!"=="Y" (
    echo.
    echo   !CYAN![~] Launching AI...!RESET!
    echo.
    call "%USB_ROOT%Start_AI.bat"
    exit /b
)
if /I "!LAUNCH_NOW!"=="N" (
    echo.
    echo   !GREEN!All done! Run 'Start_AI.bat' whenever you're ready.!RESET!
    echo.
    pause
    exit /b
)
echo   !RED![ERROR] Please select Y or N.!RESET!
goto prompt_launch
