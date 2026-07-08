# Run all tests (including SyncTest) headless.
# Note: keep this file ASCII-only. PowerShell 5.1 misreads UTF-8 without BOM.
# Safety net: GDScript runtime errors abort a test method silently, so if the
# output contains SCRIPT ERROR while the exit code is 0, force failure.
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found: $godot (see README)"
    exit 1
}
$out = & $godot --headless --path $PSScriptRoot --script res://tests/run_tests.gd 2>&1 | ForEach-Object { $_.ToString() }
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Host $_ }
if (($code -eq 0) -and ($out | Where-Object { $_ -match "SCRIPT ERROR" })) {
    Write-Host "SCRIPT ERROR detected in output: forcing exit 1"
    exit 1
}
exit $code
