<#
.SYNOPSIS
  Brings the whole backend up: MongoDB replica set, the API, and the checks
  that decide whether a phone can actually reach it.

.DESCRIPTION
  Neither process survives a reboot or a long sleep, and when they are down the
  app reports "can't sign in" — which looks like a broken app rather than a
  stopped server. This is the one command that puts it all back.

  It also compares the machine's current LAN address against the one baked into
  the last APK build. Those two failures are indistinguishable from the phone
  (both are just a sign-in that never completes), but the fixes are opposite:
  a stopped server needs starting, a moved server needs the address override on
  the sign-in screen. So the script says which one it is.

.PARAMETER Restart
  Kill an API already listening on 4000 and start a fresh one. Use after
  changing backend code; without it, a running server is left alone.

.EXAMPLE
  .\scripts\start-server.ps1
  .\scripts\start-server.ps1 -Restart
#>
[CmdletBinding()]
param(
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $projectRoot 'backend'
$apiPort = 4000

function Test-Port($port) {
    $null -ne (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
}

function Get-LanAddress {
    # The adapter carrying the default route is the one the phone can reach.
    # Picking by name ("WiFi") breaks the moment somebody plugs in Ethernet.
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        $address = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1
        if ($address) { return $address.IPAddress }
    }
    $fallback = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -First 1
    if ($fallback) { return $fallback.IPAddress }
    throw 'No usable IPv4 address found.'
}

Write-Host ''
Write-Host ('=' * 64)
Write-Host '  GWD Club OS - starting the backend'
Write-Host ('=' * 64)

# --- 1. MongoDB ------------------------------------------------------------
# Port 27018. The mongod on 27017 is this machine's unrelated Windows service.
if (Test-Port 27018) {
    Write-Host '  [1/4] MongoDB   already up on 27018' -ForegroundColor Green
} else {
    Write-Host '  [1/4] MongoDB   starting replica set on 27018...' -ForegroundColor Cyan
    & (Join-Path $backend 'scripts\start-mongo.ps1')
    if (-not (Test-Port 27018)) { throw 'MongoDB did not come up on 27018.' }
}

# --- 2. API ----------------------------------------------------------------
if ((Test-Port $apiPort) -and $Restart) {
    Write-Host "  [2/4] API        stopping the server on $apiPort..." -ForegroundColor Cyan
    Get-NetTCPConnection -State Listen -LocalPort $apiPort -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

if (Test-Port $apiPort) {
    Write-Host "  [2/4] API        already up on $apiPort  (-Restart to replace it)" -ForegroundColor Green
} else {
    Write-Host "  [2/4] API        starting..." -ForegroundColor Cyan
    Start-Process -FilePath 'node' -ArgumentList 'src/index.js' `
        -WorkingDirectory $backend `
        -RedirectStandardOutput (Join-Path $backend 'server.log') `
        -RedirectStandardError  (Join-Path $backend 'server.err.log') `
        -WindowStyle Hidden

    $up = $false
    foreach ($i in 1..30) {
        Start-Sleep -Seconds 1
        if (Test-Port $apiPort) { $up = $true; break }
    }
    if (-not $up) {
        Write-Host ''
        Write-Warning "The API never started listening on $apiPort. Last lines of server.err.log:"
        if (Test-Path (Join-Path $backend 'server.err.log')) {
            Get-Content (Join-Path $backend 'server.err.log') -Tail 20
        }
        throw 'Backend failed to start.'
    }
}

# --- 3. Does it actually answer? -------------------------------------------
$ip = Get-LanAddress
$base = "http://${ip}:$apiPort"
try {
    $health = Invoke-RestMethod -Uri "$base/api/health" -TimeoutSec 8
    Write-Host "  [3/4] Health     ok  (mongo: $($health.mongo), live sync: $($health.changeStreams))" -ForegroundColor Green
} catch {
    Write-Host "  [3/4] Health     FAILED at $base" -ForegroundColor Red
    Write-Warning 'The server is listening but not reachable on the LAN address.'
    Write-Warning 'Usually the firewall: the inbound rule for Node.js must be enabled'
    Write-Warning 'on the profile the current network has (Get-NetConnectionProfile).'
    throw 'Health check failed.'
}

# --- 4. Does that match what the installed APK expects? --------------------
$stampFile = Join-Path $projectRoot '.last-build-ip'
$network = (Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1)
if (Test-Path $stampFile) {
    $baked = (Get-Content $stampFile -Raw).Trim()
    if ($baked -eq $ip) {
        Write-Host "  [4/4] Address    matches the last APK build" -ForegroundColor Green
    } else {
        Write-Host "  [4/4] Address    CHANGED since the last APK build" -ForegroundColor Yellow
    }
} else {
    $baked = $null
    Write-Host "  [4/4] Address    no record of the last build" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ('=' * 64)
Write-Host "  Phone / app should point at   $base"
if ($network) { Write-Host "  Network                       $($network.Name)  [$($network.NetworkCategory)]" }
Write-Host ('=' * 64)

if ($baked -and $baked -ne $ip) {
    Write-Host ''
    Write-Warning "Installed APKs were built for http://${baked}:$apiPort and will not reach this server."
    Write-Warning 'Fix without rebuilding: on the sign-in screen, open the server-address'
    Write-Warning "override and enter  $base"
}
Write-Host ''
