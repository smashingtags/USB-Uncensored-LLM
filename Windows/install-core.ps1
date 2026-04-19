# Eight.ly Stick - Windows installer
# Detects GPU, pulls the right Ollama backend, downloads models, verifies imports.

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root        = (Get-Item $PSScriptRoot).Parent.FullName
$SharedDir   = Join-Path $Root 'Shared'
$BinDir      = Join-Path $SharedDir 'bin'
$ModelsDir   = Join-Path $SharedDir 'models'
$OllamaData  = Join-Path $ModelsDir 'ollama_data'
$CatalogPath = Join-Path $SharedDir 'catalog.json'
$StateFile   = Join-Path $SharedDir 'install-state.json'

# Private install-time port, isolated from runtime (:11438) and diagnostic (:11440).
$InstallPort = if ($env:ELY_INSTALL_PORT) { [int]$env:ELY_INSTALL_PORT } else { 11439 }

New-Item -ItemType Directory -Force -Path $BinDir,$ModelsDir,$OllamaData | Out-Null

function Write-Banner { param([string]$T,[string]$C='Cyan')
    Write-Host ''; Write-Host ('=' * 58) -ForegroundColor $C
    Write-Host ('  ' + $T) -ForegroundColor $C
    Write-Host ('=' * 58) -ForegroundColor $C
}
function Write-Step { param([string]$N,[string]$T) Write-Host ("[$N] $T") -ForegroundColor Yellow }
function Write-Ok   { param([string]$T) Write-Host ("     [OK] $T") -ForegroundColor Green }
function Write-Fail { param([string]$T) Write-Host ("     [X]  $T") -ForegroundColor Red }
function Write-Info { param([string]$T) Write-Host ("       $T") -ForegroundColor DarkGray }

function New-Modelfile {
    param($m, [string]$modelsDir)
    $path = Join-Path $modelsDir ("Modelfile-" + $m.id)
    $sys  = $m.systemPrompt -replace '"','\"'
    @(
        "FROM ./$($m.file)",
        "PARAMETER temperature $($m.params.temperature)",
        "PARAMETER top_p $($m.params.top_p)",
        "SYSTEM `"$sys`""
    ) | Set-Content -Path $path -Encoding UTF8
    $path
}

if (-not (Test-Path $CatalogPath)) { Write-Fail "Missing catalog.json at $CatalogPath"; exit 2 }
$Catalog = Get-Content $CatalogPath -Raw | ConvertFrom-Json

Write-Banner ("$($Catalog.product) Setup") 'Cyan'

# ---------- GPU detection ----------
Write-Step 1 'Detecting GPU'
$gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -and $_.Name -notmatch 'Parsec|Virtual|Microsoft Basic' }
$backendKey = 'windows-cpu'
$gpuName    = 'CPU (no discrete GPU detected)'
foreach ($g in $gpus) {
    if ($g.Name -match 'Intel.*Arc|Intel.*Iris Xe MAX|Intel.*Data Center GPU') {
        $backendKey = 'windows-intel'; $gpuName = $g.Name; break
    } elseif ($g.Name -match 'NVIDIA|GeForce|Quadro|RTX|GTX') {
        $backendKey = 'windows-nvidia'; $gpuName = $g.Name; break
    } elseif ($g.Name -match 'AMD|Radeon') {
        $backendKey = 'windows-cpu'
        $gpuName = $g.Name + '  (CPU fallback - Ollama AMD Windows support is limited)'
    }
}
Write-Ok "GPU: $gpuName"
Write-Info "Backend: $($Catalog.backends.$backendKey.label)"

$backend    = $Catalog.backends.$backendKey
if (-not $backend) { Write-Fail "No backend entry for $backendKey"; exit 3 }
$backendDir = Join-Path $BinDir $backendKey
$entrypoint = Join-Path $backendDir $backend.entrypoint

# ---------- Engine install ----------
Write-Step 2 'Installing engine'
if (Test-Path $entrypoint) {
    Write-Ok "Engine already present at $backendDir"
} else {
    New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
    $archive = Join-Path $backendDir '_download.zip'
    Write-Info "Downloading $($backend.url)"
    $attempt = 0; $ok = $false
    while ($attempt -lt 3 -and -not $ok) {
        $attempt++
        & curl.exe -L --fail --ssl-no-revoke --progress-bar $backend.url -o $archive
        if ($LASTEXITCODE -eq 0 -and (Test-Path $archive)) { $ok = $true; break }
        Write-Info "Attempt $attempt failed, retrying..."
        Start-Sleep 2
    }
    if (-not $ok) { Write-Fail "Engine download failed after 3 attempts"; exit 4 }
    Write-Info 'Extracting...'
    Expand-Archive -Path $archive -DestinationPath $backendDir -Force
    Remove-Item $archive -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $entrypoint)) {
        $found = Get-ChildItem -Path $backendDir -Recurse -Filter ([System.IO.Path]::GetFileName($backend.entrypoint)) -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and $found.FullName -ne $entrypoint) { Move-Item $found.FullName $entrypoint -Force }
    }
    if (-not (Test-Path $entrypoint)) { Write-Fail "Expected entrypoint missing: $entrypoint"; exit 5 }
    Write-Ok 'Engine extracted'
}

# ---------- Model menu ----------
Write-Step 3 'Choose models to install'
$models = $Catalog.models
for ($i = 0; $i -lt $models.Count; $i++) {
    $m = $models[$i]
    Write-Host ('  [{0}] {1,-40}  {2,-7}  {3}' -f ($i+1), $m.name, $m.sizeLabel, $m.badge)
}
Write-Host '  [A] All'
Write-Host '  [R] Recommended only (Gemma 2 2B)'
Write-Host ''
$sel = Read-Host '  Enter numbers comma-separated (e.g. 1,3,5), or A / R'
$selected = @()
if ($sel -match '^[Aa]') { $selected = $models }
elseif ($sel -match '^[Rr]' -or [string]::IsNullOrWhiteSpace($sel)) {
    $selected = @($models | Where-Object { $_.id -eq 'gemma2-2b' })
} else {
    foreach ($part in ($sel -split '\s*,\s*')) {
        if ($part -match '^\d+$') {
            $idx = [int]$part - 1
            if ($idx -ge 0 -and $idx -lt $models.Count) { $selected += $models[$idx] }
        }
    }
}
if (-not $selected) { Write-Fail 'No valid models selected'; exit 6 }
Write-Ok ("Selected: " + (($selected | ForEach-Object { $_.name }) -join ', '))

# ---------- Download weights ----------
Write-Step 4 'Downloading model weights'
foreach ($m in $selected) {
    $dest = Join-Path $ModelsDir $m.file
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt ([int64]$m.sizeBytes * 0.9))) {
        Write-Ok "$($m.name) already downloaded"
        continue
    }
    Write-Info "Downloading $($m.name) ($($m.sizeLabel)) ..."
    $attempt = 0; $ok = $false
    while ($attempt -lt 3 -and -not $ok) {
        $attempt++
        & curl.exe -L --fail --ssl-no-revoke --progress-bar -C - $m.url -o $dest
        if ($LASTEXITCODE -eq 0 -and (Test-Path $dest) -and ((Get-Item $dest).Length -gt ([int64]$m.sizeBytes * 0.9))) { $ok = $true; break }
        Write-Info "Attempt $attempt failed, retrying..."
        Start-Sleep 3
    }
    if (-not $ok) { Write-Fail "Download of $($m.name) failed"; continue }
    Write-Ok "$($m.name) downloaded"
}

# ---------- Assign models to engines (primary vs secondary) ----------
# Every selected model gets an engine. If the model has supportedBackends set
# and the primary backend is not in it, we try to satisfy it with one of the
# listed secondaries (e.g. windows-intel-llamacpp for Gemma 4 on Arc).
$secondaryBackendsNeeded = @{}
$modelEngine = @{}
$primaryPlatform = ($backendKey -split '-')[0]
foreach ($m in $selected) {
    $sup = @($m.supportedBackends)
    if (-not $sup -or $sup.Count -eq 0 -or $sup -contains $backendKey) {
        $modelEngine[$m.id] = $backendKey
    } else {
        $chosen = $null
        foreach ($b in $sup) {
            if ($Catalog.backends.$b -and $b -like "$primaryPlatform-*") { $chosen = $b; break }
        }
        if (-not $chosen) {
            foreach ($b in $sup) {
                if ($Catalog.backends.$b) { $chosen = $b; break }
            }
        }
        if ($chosen) {
            $modelEngine[$m.id] = $chosen
            $secondaryBackendsNeeded[$chosen] = $true
        } else {
            Write-Fail "$($m.name) - no backend in supportedBackends is known in catalog"
            $modelEngine[$m.id] = $null
        }
    }
}
if ($secondaryBackendsNeeded.Count -gt 0) {
    Write-Info ("Secondary engines needed: " + ($secondaryBackendsNeeded.Keys -join ', '))
}

# ---------- Install any secondary backends ----------
foreach ($secKey in $secondaryBackendsNeeded.Keys) {
    $sec = $Catalog.backends.$secKey
    $secDir = Join-Path $BinDir $secKey
    $secEntry = Join-Path $secDir $sec.entrypoint
    if (Test-Path $secEntry) {
        Write-Ok "Secondary engine already present: $secKey"
        continue
    }
    New-Item -ItemType Directory -Force -Path $secDir | Out-Null
    $secArchive = Join-Path $secDir '_download.zip'
    Write-Info "Downloading secondary engine $secKey ($($sec.url))"
    $attempt = 0; $ok = $false
    while ($attempt -lt 3 -and -not $ok) {
        $attempt++
        & curl.exe -L --fail --ssl-no-revoke --progress-bar $sec.url -o $secArchive
        if ($LASTEXITCODE -eq 0 -and (Test-Path $secArchive)) { $ok = $true; break }
        Start-Sleep 2
    }
    if (-not $ok) { Write-Fail "Secondary engine $secKey download failed"; continue }
    Expand-Archive -Path $secArchive -DestinationPath $secDir -Force
    Remove-Item $secArchive -Force -ErrorAction SilentlyContinue
    # Flatten if binaries landed in a nested dir
    if (-not (Test-Path $secEntry)) {
        $found = Get-ChildItem -Path $secDir -Recurse -Filter ([System.IO.Path]::GetFileName($sec.entrypoint)) -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $srcDir = Split-Path $found.FullName -Parent
            Get-ChildItem -Path $srcDir | Move-Item -Destination $secDir -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path $secEntry) { Write-Ok "Secondary engine installed: $secKey" }
    else { Write-Fail "Secondary engine entrypoint not found after extract: $secEntry" }
}

# ---------- Import models ----------
Write-Step 5 'Registering models with the engine'
Get-Process ollama,ollama-lib,ollama-windows -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

$envMap = @{}
$backend.env.PSObject.Properties | ForEach-Object { $envMap[$_.Name] = $_.Value }
$envMap['OLLAMA_MODELS'] = $OllamaData
$envMap['OLLAMA_HOST']   = "127.0.0.1:$InstallPort"
$envMap.GetEnumerator() | ForEach-Object { Set-Item -Path "env:$($_.Key)" -Value $_.Value }

$serveJob = Start-Job -ScriptBlock {
    param($entry,$dir,$em)
    foreach ($k in $em.Keys) { Set-Item -Path "env:$k" -Value $em[$k] }
    Set-Location $dir
    & $entry serve 2>&1
} -ArgumentList $entrypoint,$backendDir,$envMap

Start-Sleep 6
$up = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$InstallPort/api/tags" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $up = $true; break }
    } catch {}
    Start-Sleep 1
}
if (-not $up) {
    Write-Fail 'Engine failed to start'
    Receive-Job $serveJob | Select-Object -Last 20 | ForEach-Object { Write-Info $_ }
    Stop-Job $serveJob -ErrorAction SilentlyContinue
    exit 7
}
Write-Ok 'Engine online'

$imported = @()
$importedEngine = @{}
foreach ($m in $selected) {
    $gguf = Join-Path $ModelsDir $m.file
    if (-not (Test-Path $gguf)) { Write-Info "Skip $($m.name) - file missing"; continue }

    $eng = $modelEngine[$m.id]
    if (-not $eng) { Write-Info "Skip $($m.name) - no compatible engine"; continue }

    $mfPath = New-Modelfile $m $ModelsDir

    # llama.cpp engines don't have an Ollama registry - just record the GGUF + Modelfile
    if ($eng -ne $backendKey) {
        Write-Ok "$($m.name) -> $eng (GGUF placed, llama-server will load at start)"
        $imported += $m
        $importedEngine[$m.id] = $eng
        continue
    }

    Push-Location $ModelsDir
    Write-Info "Creating $($m.id)..."
    $createOutput = & $entrypoint create $m.id -f $mfPath 2>&1
    $createRc = $LASTEXITCODE
    Pop-Location

    if ($createRc -ne 0) {
        Write-Fail "$($m.name) - ollama create failed (rc=$createRc)"
        $createOutput | Select-Object -Last 5 | ForEach-Object { Write-Info $_ }
        continue
    }

    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:$InstallPort/api/tags" -TimeoutSec 5
        if (($tags.models | Where-Object { $_.name -match "^$($m.id):" })) {
            Write-Ok "$($m.name) registered"
            $imported += $m
            $importedEngine[$m.id] = $backendKey
        } else {
            Write-Fail "$($m.name) - created but manifest not visible"
        }
    } catch {
        Write-Fail "$($m.name) - manifest check failed: $_"
    }
}

# ---------- Smoke test ----------
$smokeTps = 0
if ($imported.Count -gt 0) {
    Write-Step 6 'Smoke test (proves acceleration)'
    $testModel = ($imported | Where-Object { $_.id -eq 'gemma2-2b' } | Select-Object -First 1)
    if (-not $testModel) { $testModel = $imported[0] }

    Write-Info "Warming up $($testModel.id) (first Intel run JIT-compiles SYCL kernels)..."
    $warm = @{ model = $testModel.id; prompt = 'Hi'; stream = $false; options = @{ num_predict = 8 } } | ConvertTo-Json
    try { $null = Invoke-RestMethod -Uri "http://127.0.0.1:$InstallPort/api/generate" -Method Post -Body $warm -ContentType 'application/json' -TimeoutSec 180 } catch {}

    Write-Info 'Timed 100-token generation...'
    $body = @{ model = $testModel.id; prompt = 'Write 100 words about the future of portable AI.'; stream = $false; options = @{ num_predict = 100; temperature = 0.7 } } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$InstallPort/api/generate" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 180
        $evalMs = [math]::Round($r.eval_duration / 1000000)
        $smokeTps = if ($evalMs -gt 0) { [math]::Round($r.eval_count * 1000.0 / $evalMs, 2) } else { 0 }
        Write-Ok ("Throughput: {0} tok/s  ({1} tokens in {2} ms)" -f $smokeTps, $r.eval_count, $evalMs)
    } catch {
        Write-Fail "Smoke test failed: $_"
    }
}

Get-Process ollama,ollama-lib -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Job $serveJob -ErrorAction SilentlyContinue
Remove-Job $serveJob -ErrorAction SilentlyContinue

# ---------- Persist state ----------
$installedLines = foreach ($m in $imported) { "$($m.id)|$($m.name)|$($m.quality)" }
$installedLines | Set-Content -Path (Join-Path $ModelsDir 'installed-models.txt') -Encoding UTF8

$secondaryList = @()
foreach ($secKey in $secondaryBackendsNeeded.Keys) {
    $sec = $Catalog.backends.$secKey
    $secondaryList += @{
        key        = $secKey
        label      = $sec.label
        entrypoint = (Join-Path "Shared\bin\$secKey" $sec.entrypoint)
    }
}

$state = @{
    product           = $Catalog.product
    version           = $Catalog.version
    backend           = $backendKey
    backendLabel      = $backend.label
    gpu               = $gpuName
    entrypoint        = (Join-Path "Shared\bin\$backendKey" $backend.entrypoint)
    installedAt       = (Get-Date -Format 'o')
    smokeTokensPerSec = $smokeTps
    secondaryBackends = $secondaryList
    installed         = $imported | ForEach-Object { @{ id = $_.id; name = $_.name; file = $_.file; engine = $importedEngine[$_.id] } }
}
$state | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding UTF8

Write-Banner 'Install summary' 'Green'
Write-Host "  Backend:     $($backend.label)"
Write-Host "  GPU:         $gpuName"
Write-Host "  Models:      $($imported.Count) of $($selected.Count) selected"
$imported | ForEach-Object { Write-Host ("    - " + $_.name) }
if ($smokeTps -gt 0) {
    Write-Host ("  Throughput:  {0} tok/s" -f $smokeTps)
    if ($backendKey -eq 'windows-intel' -and $smokeTps -lt 25) {
        Write-Host "  WARNING: low throughput for Arc GPU. Update driver: https://intel.com/arc-drivers" -ForegroundColor Yellow
    }
}
Write-Host ''
if ($imported.Count -eq 0) { exit 8 }
exit 0
