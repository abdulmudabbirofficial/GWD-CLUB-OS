<#
.SYNOPSIS
  The whole backend suite, against throwaway databases, then cleans up.

.DESCRIPTION
  Three suites, two isolated databases:

    smoke.js           the API end to end            gwd_club_os_smoke  (4100)
    test-reminders.js  the daily nudge sweep         same database
    test-meetings.js   meetings + attendance         gwd_club_os_meet   (4500)

  Meetings needs its own database because it signs in as the real roster
  (president@gwd.global, tech@gwd.global, production@gwd.global) and asserts on
  the Leads by name. smoke.js invents its own throwaway people, and mixing the
  two makes each suite's failures depend on the other's fixtures.

  The club's own database on 4000 is never opened, and the server running
  there is left alone.

.PARAMETER Keep
  Leave the throwaway databases behind for inspection after a failure.

.PARAMETER Only
  Run one suite: smoke or meetings.

.EXAMPLE
  .\scripts\test-all.ps1
  .\scripts\test-all.ps1 -Only meetings -Keep
#>
[CmdletBinding()]
param(
    [switch]$Keep,
    [ValidateSet('all', 'smoke', 'meetings')]
    [string]$Only = 'all'
)

$ErrorActionPreference = 'Stop'
$backend = Split-Path -Parent $PSScriptRoot
$mongosh = 'D:\dev\gwd-toolchain\mongosh\bin\mongosh.exe'
$failed = 0

# The LOCAL replica set, always. Overriding only MONGODB_DB is not isolation:
# .env points MONGODB_URI at Atlas, so a throwaway database name alone runs the
# whole suite on the live cluster and leaves it there. Both the server and the
# seeding script below read this, so both have to be told.
$localUri = 'mongodb://127.0.0.1:27018/?replicaSet=rs0&directConnection=true'

function Drop-Database([string]$name) {
    if ($Keep -or -not (Test-Path $mongosh)) { return }
    & $mongosh --quiet --eval 'db.dropDatabase()' `
        "mongodb://127.0.0.1:27018/$name`?directConnection=true" | Out-Null
    Write-Host "  Dropped '$name'." -ForegroundColor DarkGray
}

# ------------------------------------------------------- process behaviour ---
# Needs no server and no database: it spawns scripts and checks they end.
if ($Only -eq 'all') {
    & node (Join-Path $PSScriptRoot 'test-exit.js')
    if ($LASTEXITCODE -ne 0) { $failed = 1 }
}

# ------------------------------------------------------------------ smoke ---
if ($Only -in @('all', 'smoke')) {
    $smoke = Join-Path $PSScriptRoot 'smoke-isolated.ps1'
    if ($Keep) { & $smoke -Keep } else { & $smoke }
    if ($LASTEXITCODE -ne 0) { $failed = 1 }
}

# --------------------------------------------------------------- meetings ---
if ($Only -in @('all', 'meetings')) {
    $port = 4500
    $dbName = 'gwd_club_os_meet'

    # Reclaim the port from a previous run that was interrupted.
    #
    # 4500 is this script's own throwaway port and nothing else uses it, so a
    # listener here is always a server we started and failed to stop - usually
    # because the run was cancelled mid-suite. Refusing outright meant one
    # interrupted run left the whole suite unrunnable until somebody went
    # hunting for a PID, which is a poor trade for a port we own. Only a `node`
    # process is taken, so an unrelated program squatting the port still stops
    # us rather than being killed.
    $held = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($owner in $held) {
        $proc = Get-Process -Id $owner -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq 'node') {
            Write-Host "  Reclaiming port $port from a previous run (pid $owner)." -ForegroundColor DarkGray
            Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        } else {
            throw "Port $port is held by $($proc.ProcessName) (pid $owner), which is not ours."
        }
    }

    Write-Host ''
    Write-Host "  Starting a throwaway API on $port against '$dbName'..." -ForegroundColor Cyan

    $env:PORT = "$port"
    $env:MONGODB_DB = $dbName
    $env:MONGODB_URI = $localUri
    $outLog = Join-Path $backend 'meet-server.log'
    $errLog = Join-Path $backend 'meet-server.err.log'

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
            throw 'Meetings test server failed to start.'
        }

        # The real roster, so the suite can assert on Dikshit and Rehman by
        # name. Passwords are printed once and captured here rather than being
        # hardcoded anywhere -- a fixed test password in the repo is a password
        # that eventually ships.
        Write-Host '  Seeding the roster...' -ForegroundColor Cyan
        $seedOut = & node (Join-Path $backend 'scripts\seed-club.js') 2>&1 | Out-String

        # seed-club.js prints where it connected. If that ever says anything but
        # local, the suite is about to write to a real cluster - stop before it
        # does, rather than discovering it later in a database listing.
        if ($seedOut -notmatch 'Target:\s*local') {
            Write-Host $seedOut
            throw 'The seed did not connect to the local replica set. Refusing to run.'
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host $seedOut
            throw 'Roster seed failed.'
        }

        $creds = @{}
        foreach ($line in ($seedOut -split "`r?`n")) {
            if ($line -match '(\S+)@gwd\.global\s+(gwd-\S+)') {
                $creds[$Matches[1]] = $Matches[2]
            }
        }
        foreach ($who in @('president', 'tech', 'production')) {
            if (-not $creds.ContainsKey($who)) {
                Write-Host $seedOut
                throw "Could not read the seeded password for $who@gwd.global."
            }
        }

        Write-Host '  Running the suite...' -ForegroundColor Cyan
        Write-Host ''
        $env:MEET_BASE = "http://127.0.0.1:$port"
        $env:MEET_CREDS = ($creds | ConvertTo-Json -Compress)
        & node (Join-Path $backend 'scripts\test-meetings.js')
        if ($LASTEXITCODE -ne 0) { $failed = 1 }
    } finally {
        if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item Env:\PORT, Env:\MONGODB_DB, Env:\MONGODB_URI, Env:\MEET_BASE, Env:\MEET_CREDS -ErrorAction SilentlyContinue
        Drop-Database $dbName
    }
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host '  All backend suites passed.' -ForegroundColor Green
} else {
    Write-Host '  Something failed. See above.' -ForegroundColor Red
}
exit $failed
