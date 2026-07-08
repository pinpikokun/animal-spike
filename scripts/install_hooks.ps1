# Install the pre-commit hook. Every commit runs the full test suite.
# Note: keep this file ASCII-only. PowerShell 5.1 misreads UTF-8 without BOM.
$root = Split-Path $PSScriptRoot -Parent
$hook = Join-Path $root ".git\hooks\pre-commit"
$body = @'
#!/bin/sh
cd "$(git rev-parse --show-toplevel)" || exit 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1
'@
[System.IO.File]::WriteAllText($hook, $body.Replace("`r`n", "`n"))
Write-Host "pre-commit hook installed: $hook"
