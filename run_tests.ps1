# Run all tests (including SyncTest) headless.
# Note: keep this file ASCII-only. PowerShell 5.1 misreads UTF-8 without BOM.
# Safety net: GDScript runtime errors abort a test method silently.
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found: $godot (see README)"
    exit 1
}
$out = & $godot --headless --path $PSScriptRoot --script res://tests/run_tests.gd 2>&1 | ForEach-Object { $_.ToString() }
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Host $_ }
$scriptErrors = @($out | Where-Object { $_ -match "SCRIPT ERROR" })
$locations = @($out | ForEach-Object {
    $match = [regex]::Match($_, "(res://[^():\s]+:\d+)")
    if ($match.Success) {
        $match.Groups[1].Value
    }
} | Group-Object | Sort-Object Count -Descending)
Write-Host ("SCRIPT ERROR summary: {0} occurrence(s)" -f $scriptErrors.Count)
if ($scriptErrors.Count -gt 0) {
    $locations | Select-Object -First 5 | ForEach-Object {
        Write-Host ("  {0}x {1}" -f $_.Count, $_.Name)
    }
    exit 1
}
exit $code
