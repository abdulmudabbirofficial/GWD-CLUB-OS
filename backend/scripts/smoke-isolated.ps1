<#
.SYNOPSIS
  Runs the smoke suite against a throwaway database, then deletes it.

.DESCRIPTION
  `smoke.js` creates accounts, departments, tasks and events. That is fine on an
  empty dev database and wrong once the club is actually using the app — the
  test's throwaway members turn up in the real member directory and never leave.

  So this starts a *second* API on its own port against its own database, runs
  the suite there, stops it, and drops the database. The club's data is never
  opened.

  The running server on 4000 is left completely alone.

.PARAMETER Keep
  Leave the throwaway database behind for inspection after a failure.

.EXAMPLE
  .\scripts\smoke-isolated.ps1
#>
[CmdletBinding()]
param(
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$backend = Split-Path -Parent $PSScriptRoot
$port = 4100
$dbName = 'gwd_club_os_smoke'
$mongosh = 'D:\dev\gwd-toolchain\mongosh\bin\mongosh.exe'

if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
    throw "Port $port is already in use; a previous isolated run may still be up."
}

Write-Host ''
Write-Host "  Starting a throwaway API on $port against '$dbName'..." -ForegroundColor Cyan

$env:PORT = "$port"
$env:MONGODB_DB = $dbName
$outLog = Join-Path $backend 'smoke-server.log'
$errLog = Join-Path $backend 'smoke-server.err.log'

$proc = Start-Process -FilePath 'node' -ArgumentList 'src/index.js' `
    -WorkingDirectory $backend `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
    -WindowStyle Hidden -PassThru

try {
    $up = $false
    foreach ($i in 1..30) {
        Start-Sleep -Seconds 1
        if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) { $up = $true; break }
    }
    if (-not $up) {
        Write-Warning 'The throwaway API never started. Last errors:'
        if (Test-Path $errLog) { Get-Content $errLog -Tail 20 }
        throw 'Isolated smoke server failed to start.'
    }

    Write-Host '  Running the suite...' -ForegroundColor Cyan
    Write-Host ''
    $env:SMOKE_BASE = "http://127.0.0.1:$port"
    & node (Join-Path $backend 'scripts\smoke.js')
    $code = $LASTEXITCODE

    # The daily reminder sweep has no route in front of it, so it is tested
    # directly rather than over HTTP — same throwaway database, same cleanup.
    if ($code -eq 0) {
        & node (Join-Path $backend 'scripts\test-reminders.js')
        $code = $LASTEXITCODE
    }
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\PORT, Env:\MONGODB_DB, Env:\SMOKE_BASE -ErrorAction SilentlyContinue

    if (-not $Keep -and (Test-Path $mongosh)) {
        & $mongosh --quiet --eval 'db.dropDatabase()' `
            "mongodb://127.0.0.1:27018/$dbName`?directConnection=true" | Out-Null
        Write-Host ''
        Write-Host "  Dropped '$dbName'. The club's database was never touched." -ForegroundColor DarkGray
    }
}

exit $code
