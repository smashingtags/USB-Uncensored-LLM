# Eight.ly Stick - diagnostic report
# Dumps system + GPU + engine info, runs a throughput benchmark so you can
# prove GPU acceleration is actually happening (and not silently CPU-bound).

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root      = (Get-Item $PSScriptRoot).Parent.FullName
$SharedDir = Join-Path $Root 'Shared'
$StatePath = Join-Path $SharedDir 'install-state.json'
$CatalogPath = Join-Path $SharedDir 'catalog.json'

function H1 { param($T) Write-Host ''; Write-Host ('=' * 58) -ForegroundColor Cyan; Write-Host ('  ' + $T) -ForegroundColor Cyan; Write-Host ('=' * 58) -ForegroundColor Cyan }
function KV { param($K,$V) Write-Host ('  {0,-20} {1}' -f $K, $V) }

H1 'EIGHT.LY STICK - DIAGNOSTIC REPORT'

KV 'Time'     (Get-Date -Format 'u')
KV 'Host'     $env:COMPUTERNAME
KV 'OS'       ((Get-CimInstance Win32_OperatingSystem).Caption)
KV 'CPU'      ((Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim())
KV 'RAM (GB)' ([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1))

$gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -and $_.Name -notmatch 'Parsec|Virtual|Microsoft Basic' }
foreach ($g in $gpus) {
    KV 'GPU' ("$($g.Name)  (driver $($g.DriverVersion))")
}

if (-not (Test-Path $StatePath)) {
    Write-Host ''
    Write-Host '  No install-state.json found. Run Windows\install.bat first.' -ForegroundColor Yellow
    exit 1
}
$state   = Get-Content -Raw $StatePath   | ConvertFrom-Json
$catalog = Get-Content -Raw $CatalogPath | ConvertFrom-Json

H1 'Install state'
KV 'Product'      ("$($state.product) v$($state.version)")
KV 'Backend'      $state.backendLabel
KV 'GPU at install' $state.gpu
KV 'Engine path'  $state.entrypoint
KV 'Installed at' $state.installedAt

Write-Host '  Models:' -ForegroundColor DarkGray
$installed = @($state.installed)
foreach ($m in $installed) { Write-Host "    - $($m.name)  ($($m.file))" }

$entry = Join-Path $Root $state.entrypoint
if (-not (Test-Path $entry)) {
    Write-Host ''
    Write-Host "  MISSING engine binary at $entry" -ForegroundColor Red
    Write-Host '  Re-run Windows\install.bat to repair.' -ForegroundColor Red
    exit 2
}
$verOut = & $entry --version 2>&1
KV 'Engine version' ($verOut -join ' ')

# ---------- Benchmark ----------
H1 'Benchmark'
Write-Host '  Running 100-token throughput test (first Intel run JIT-compiles SYCL kernels)...' -ForegroundColor Yellow

Get-Process ollama,ollama-lib,ollama-windows -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

$envMap = @{}
$catalog.backends.($state.backend).env.PSObject.Properties | ForEach-Object { $envMap[$_.Name] = $_.Value }
$envMap['OLLAMA_MODELS'] = (Join-Path $SharedDir 'models\ollama_data')
$envMap['OLLAMA_HOST']   = '127.0.0.1:11440'

$backendDir = Join-Path $SharedDir "bin\$($state.backend)"
$job = Start-Job -ScriptBlock {
    param($e,$d,$em)
    foreach ($k in $em.Keys) { Set-Item -Path "env:$k" -Value $em[$k] }
    Set-Location $d
    & $e serve 2>&1
} -ArgumentList $entry, $backendDir, $envMap

Start-Sleep 6
$up = $false
for ($i = 0; $i -lt 15; $i++) {
    try { if ((Invoke-WebRequest 'http://127.0.0.1:11440/api/tags' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $up = $true; break } } catch {}
    Start-Sleep 1
}
if (-not $up) {
    Write-Host '  Engine failed to start.' -ForegroundColor Red
    Receive-Job $job | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Stop-Job $job -ErrorAction SilentlyContinue
    exit 3
}

$modelId = ($installed | Select-Object -First 1).id
if (-not $modelId) { Write-Host '  No models installed.' -ForegroundColor Red; Stop-Job $job; exit 4 }

$warm = @{ model = $modelId; prompt = 'Hi'; stream = $false; options = @{ num_predict = 8 } } | ConvertTo-Json
try { $null = Invoke-RestMethod 'http://127.0.0.1:11440/api/generate' -Method Post -Body $warm -ContentType 'application/json' -TimeoutSec 180 } catch {}

$body = @{ model = $modelId; prompt = 'Write 100 words about the future of portable AI.'; stream = $false; options = @{ num_predict = 100; temperature = 0.7 } } | ConvertTo-Json
try {
    $r = Invoke-RestMethod 'http://127.0.0.1:11440/api/generate' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 180
    $evalMs = [math]::Round($r.eval_duration / 1000000)
    $tps = if ($evalMs -gt 0) { [math]::Round($r.eval_count * 1000.0 / $evalMs, 2) } else { 0 }
    KV 'Model tested'   $modelId
    KV 'Tokens gen.'    $r.eval_count
    KV 'Eval duration'  ("$evalMs ms")
    KV 'Throughput'     ("$tps tok/s")
    Write-Host ''
    if ($state.backend -eq 'windows-intel') {
        if ($tps -ge 40)    { Write-Host '  VERDICT: Arc GPU firing on all cylinders.' -ForegroundColor Green }
        elseif ($tps -ge 20){ Write-Host '  VERDICT: GPU active, below expected. Check driver / power plan.' -ForegroundColor Yellow }
        else                { Write-Host '  VERDICT: Likely CPU-bound. Update Intel Arc driver and re-run.' -ForegroundColor Red }
    } elseif ($state.backend -eq 'windows-cpu') {
        Write-Host '  VERDICT: CPU backend. Expect 8-15 tok/s depending on model and CPU.' -ForegroundColor Yellow
    } else {
        Write-Host "  VERDICT: throughput is $tps tok/s for $($state.backend)."
    }
} catch {
    Write-Host ("  Benchmark FAILED: $_") -ForegroundColor Red
}

Get-Process ollama,ollama-lib -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -ErrorAction SilentlyContinue
