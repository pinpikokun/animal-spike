# Run all tests (including SyncTest) headless.
# Note: keep this file ASCII-only. PowerShell 5.1 misreads UTF-8 without BOM.
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found: $godot (see README)"
    exit 1
}
& $godot --headless --path $PSScriptRoot --script res://tests/run_tests.gd
exit $LASTEXITCODE
