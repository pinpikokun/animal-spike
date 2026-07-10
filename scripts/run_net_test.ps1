# Launch two windowed instances on one PC for the phase-1 net test.
# ASCII comments only (PowerShell 5.1 misreads UTF-8 without BOM).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_net_test.ps1 [-Bot]
# -Bot makes both sides play with the deterministic CPU (unattended soak).
param([switch]$Bot)

$root = Split-Path $PSScriptRoot -Parent
$godot = Join-Path $root "tools\godot\Godot_v4.6-stable_win64.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found: $godot (see README)"
    exit 1
}

$hostArgs = @("--path", $root, "--", "host")
$joinArgs = @("--path", $root, "--", "join", "127.0.0.1")
if ($Bot) {
    $hostArgs += "bot"
    $joinArgs += "bot"
}

Write-Host "Launching host..."
Start-Process $godot -ArgumentList $hostArgs
Start-Sleep -Seconds 2
Write-Host "Launching join (127.0.0.1)..."
Start-Process $godot -ArgumentList $joinArgs
Write-Host "Two windows launched. Front window receives keyboard input."
