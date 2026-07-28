# Launch two instances on one PC for the phase-1 net test.
# ASCII comments only (PowerShell 5.1 misreads UTF-8 without BOM).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_net_test.ps1 [-Bot]
# -Bot makes both sides play with the deterministic CPU (unattended soak).
# -VerifyBootSeed runs a short headless handshake check and saves four log files.
param(
    [switch]$Bot,
    [switch]$VerifyBootSeed,
    [string]$LogDir = ""
)

$root = Split-Path $PSScriptRoot -Parent
$godot = Join-Path $root "tools\godot\Godot_v4.6-stable_win64.exe"
$hostSyncStartedLine = "NET SYNC STARTED role=host"
$joinSyncStartedLine = "NET SYNC STARTED role=join"

function Read-LogLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Log file not found: $Path"
    }
    try {
        return @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    }
    catch {
        throw ("Failed to read log file {0}: {1}" -f $Path, $_.Exception.Message)
    }
}

function Find-ExactLogLines {
    param(
        [string[]]$Lines,
        [string]$Expected
    )
    return @($Lines | Where-Object { $_ -ceq $Expected })
}

if (-not $VerifyBootSeed) {
    if (-not (Test-Path $godot)) {
        Write-Host "Godot not found: $godot (see README)"
        exit 1
    }
    $rootArg = '"' + $root + '"'
    $hostArgs = @("--path", $rootArg, "--", "host")
    $joinArgs = @("--path", $rootArg, "--", "join", "127.0.0.1")
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
    exit 0
}

if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $LogDir = Join-Path ([IO.Path]::GetTempPath()) "animal-spike-net-boot-seed-$stamp"
}
$LogDir = [IO.Path]::GetFullPath($LogDir)
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$hostOut = Join-Path $LogDir "host.stdout.log"
$hostErr = Join-Path $LogDir "host.stderr.log"
$joinOut = Join-Path $LogDir "join.stdout.log"
$joinErr = Join-Path $LogDir "join.stderr.log"
$rootArg = '"' + $root + '"'
$hostArgs = @("--headless", "--path", $rootArg, "--", "host", "bot")
$joinArgs = @("--headless", "--path", $rootArg, "--", "join", "127.0.0.1", "bot")
$hostProcess = $null
$joinProcess = $null
$failure = $null
foreach ($log in @($hostOut, $hostErr, $joinOut, $joinErr)) {
    New-Item -ItemType File -Path $log -Force | Out-Null
}

try {
    if (-not (Test-Path $godot)) {
        throw "Godot not found: $godot (see README)"
    }
    $hostProcess = Start-Process $godot -ArgumentList $hostArgs -PassThru `
        -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr
    Start-Sleep -Seconds 1
    $joinProcess = Start-Process $godot -ArgumentList $joinArgs -PassThru `
        -RedirectStandardOutput $joinOut -RedirectStandardError $joinErr

    $deadline = (Get-Date).AddSeconds(30)
    $bothStarted = $false
    while ((Get-Date) -lt $deadline) {
        $hostLines = @(Read-LogLines -Path $hostOut)
        $joinLines = @(Read-LogLines -Path $joinOut)
        $hostStarted = @(Find-ExactLogLines -Lines $hostLines -Expected $hostSyncStartedLine)
        $joinStarted = @(Find-ExactLogLines -Lines $joinLines -Expected $joinSyncStartedLine)
        if ($hostStarted.Count -ge 1 -and $joinStarted.Count -ge 1) {
            $bothStarted = $true
            break
        }
        if ($hostProcess.HasExited) {
            $failure = "Host exited before both sync-start lines were observed."
            break
        }
        if ($joinProcess.HasExited) {
            $failure = "Join exited before both sync-start lines were observed."
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $bothStarted -and $null -eq $failure) {
        $failure = "Timed out waiting 30 seconds for both sync-start lines."
    }
    if ($bothStarted) {
        Start-Sleep -Seconds 2
        if ($hostProcess.HasExited -or $joinProcess.HasExited) {
            $failure = "A child process exited during the two-second observation window."
        }
    }
}
catch {
    $failure = "Failed to launch or monitor child processes: $($_.Exception.Message)"
}
finally {
    foreach ($process in @($hostProcess, $joinProcess)) {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
    }
}

$hostLines = @()
$hostErrorLines = @()
$joinLines = @()
$joinErrorLines = @()
try {
    $hostLines = @(Read-LogLines -Path $hostOut)
    $hostErrorLines = @(Read-LogLines -Path $hostErr)
    $joinLines = @(Read-LogLines -Path $joinOut)
    $joinErrorLines = @(Read-LogLines -Path $joinErr)
}
catch {
    if ($null -eq $failure) {
        $failure = "Failed to read final log files: $($_.Exception.Message)"
    }
}
$hostAgreed = @($hostLines | Where-Object {
    $_ -match "^NET_AGREED role=host seed=(-?\d+) roster=([0-9]+(?:,[0-9]+){3}) serving=([01]) hash=(-?\d+)$"
})
$joinAgreed = @($joinLines | Where-Object {
    $_ -match "^NET_AGREED role=join seed=(-?\d+) roster=([0-9]+(?:,[0-9]+){3}) serving=([01]) hash=(-?\d+)$"
})
$ackVerified = @($hostLines | Where-Object {
    $_ -match "^NET_ACK_VERIFIED peer=([0-9]+) seed=(-?\d+) hash=(-?\d+)$"
})
$hostStarted = @(Find-ExactLogLines -Lines $hostLines -Expected $hostSyncStartedLine)
$joinStarted = @(Find-ExactLogLines -Lines $joinLines -Expected $joinSyncStartedLine)

if ($null -eq $failure -and $hostAgreed.Count -ne 1) {
    $failure = "Expected exactly one host NET_AGREED line."
}
if ($null -eq $failure -and $joinAgreed.Count -ne 1) {
    $failure = "Expected exactly one join NET_AGREED line."
}
if ($null -eq $failure -and $ackVerified.Count -ne 1) {
    $failure = "Expected exactly one host NET_ACK_VERIFIED line."
}
if ($null -eq $failure -and $hostStarted.Count -ne 1) {
    $failure = "Expected exactly one host NET SYNC STARTED line."
}
if ($null -eq $failure -and $joinStarted.Count -ne 1) {
    $failure = "Expected exactly one join NET SYNC STARTED line."
}

if ($null -eq $failure) {
    $null = $hostAgreed[0] -match "^NET_AGREED role=host seed=(-?\d+) roster=([0-9]+(?:,[0-9]+){3}) serving=([01]) hash=(-?\d+)$"
    $hostSeed = $Matches[1]
    $hostRoster = $Matches[2]
    $hostServing = $Matches[3]
    $hostHash = $Matches[4]
    $null = $joinAgreed[0] -match "^NET_AGREED role=join seed=(-?\d+) roster=([0-9]+(?:,[0-9]+){3}) serving=([01]) hash=(-?\d+)$"
    if ($Matches[1] -ne $hostSeed -or $Matches[2] -ne $hostRoster -or
            $Matches[3] -ne $hostServing -or $Matches[4] -ne $hostHash) {
        $failure = "Host and join NET_AGREED values differ."
    }
}
if ($null -eq $failure) {
    $null = $ackVerified[0] -match "^NET_ACK_VERIFIED peer=([0-9]+) seed=(-?\d+) hash=(-?\d+)$"
    if ($Matches[2] -ne $hostSeed -or $Matches[3] -ne $hostHash) {
        $failure = "NET_ACK_VERIFIED seed or hash differs from host NET_AGREED."
    }
}
if ($null -eq $failure) {
    $hostAgreedIndex = [Array]::IndexOf($hostLines, $hostAgreed[0])
    $hostAckIndex = [Array]::IndexOf($hostLines, $ackVerified[0])
    $hostStartIndex = [Array]::IndexOf($hostLines, $hostStarted[0])
    $joinAgreedIndex = [Array]::IndexOf($joinLines, $joinAgreed[0])
    $joinStartIndex = [Array]::IndexOf($joinLines, $joinStarted[0])
    if (-not ($hostAgreedIndex -lt $hostAckIndex -and $hostAckIndex -lt $hostStartIndex)) {
        $failure = "Host log order is not AGREED, ACK_VERIFIED, SYNC STARTED."
    }
    elseif (-not ($joinAgreedIndex -lt $joinStartIndex)) {
        $failure = "Join log order is not AGREED, SYNC STARTED."
    }
}

$allLogData = @(
    [PSCustomObject]@{ Path = $hostOut; Lines = $hostLines },
    [PSCustomObject]@{ Path = $hostErr; Lines = $hostErrorLines },
    [PSCustomObject]@{ Path = $joinOut; Lines = $joinLines },
    [PSCustomObject]@{ Path = $joinErr; Lines = $joinErrorLines }
)
if ($null -eq $failure) {
    foreach ($logData in $allLogData) {
        $bad = @($logData.Lines | Where-Object {
            $_ -match "NET STATE MISMATCH|NET SYNC ERROR|SCRIPT ERROR"
        })
        if ($bad.Count -ne 0) {
            $failure = "Unexpected error marker in $($logData.Path)."
            break
        }
    }
}

Write-Host "Host stdout: $hostOut"
Write-Host "Host stderr: $hostErr"
Write-Host "Join stdout: $joinOut"
Write-Host "Join stderr: $joinErr"
if ($null -ne $failure) {
    Write-Host "BOOT SEED VERIFY FAILED: $failure"
    exit 1
}
Write-Host "BOOT SEED VERIFY PASSED"
exit 0
