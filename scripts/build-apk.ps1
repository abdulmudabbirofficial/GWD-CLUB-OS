<#
.SYNOPSIS
  Builds the release APKs with this machine's current LAN address baked in.

.DESCRIPTION
  `GWD_API_BASE` is a dart-define, so it is fixed at build time. Whenever the
  laptop's IP changes — a different Wi-Fi, a phone hotspot handing out a new
  DHCP lease — every installed APK stops reaching the backend and looks broken.

  This script removes the step where that is forgotten: it reads the live IPv4
  address off the active adapter, bakes it in, and prints what it used.

  The in-app server-address override on the sign-in screen stays the safety net
  for when the IP changes *after* a build. This only spares people from needing
  it on day one.

.PARAMETER Ip
  Override the detected address. Useful when the machine has several adapters
  up and the wrong one wins, or when building for a fixed server.

.PARAMETER Universal
  Also build the fat APK that runs on any CPU. Slower and ~60 MB; the arm64
  split is under 25 MB and covers essentially every phone from the last decade.

.EXAMPLE
  .\scripts\build-apk.ps1
  .\scripts\build-apk.ps1 -Ip 192.168.1.42 -Universal
#>
[CmdletBinding()]
param(
    [string]$Ip,
    [switch]$Universal
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $projectRoot 'app'

# --- toolchain -------------------------------------------------------------
# Portable, on D:, nothing installed into C:. See CLAUDE.md.
$toolchain = 'D:\dev\gwd-toolchain'
if (-not (Test-Path $toolchain)) {
    throw "Toolchain not found at $toolchain. See CLAUDE.md for the layout."
}
$env:JAVA_HOME = "$toolchain\jdk"
$env:ANDROID_SDK_ROOT = "$toolchain\android-sdk"
$env:ANDROID_HOME = "$toolchain\android-sdk"
$env:PATH = "$toolchain\flutter\bin;$toolchain\jdk\bin;$toolchain\git\cmd;$env:PATH"
$env:GRADLE_OPTS = '-Dorg.gradle.jvmargs=-Xmx2048m'

# --- address ---------------------------------------------------------------
function Get-LanAddress {
    # The adapter carrying the default route is the one the phone can reach.
    # Picking by name ("WiFi") breaks the moment somebody plugs in Ethernet.
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric |
        Select-Object -First 1
    if ($route) {
        $address = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne '127.0.0.1' } |
            Select-Object -First 1
        if ($address) { return $address.IPAddress }
    }
    $fallback = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -First 1
    if ($fallback) { return $fallback.IPAddress }
    throw 'No usable IPv4 address found. Pass -Ip explicitly.'
}

if (-not $Ip) { $Ip = Get-LanAddress }
$base = "http://${Ip}:4000"

$network = (Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1).Name
Write-Host ''
Write-Host ('=' * 64)
Write-Host "  Baking in  $base"
if ($network) { Write-Host "  Network    $network" }
Write-Host ('=' * 64)
Write-Host ''

# --- is the backend actually up there? -------------------------------------
# Catching this now is worth it: otherwise the APK is built, installed, and the
# failure shows up as a sign-in error on somebody else's phone.
try {
    $health = Invoke-RestMethod -Uri "$base/api/health" -TimeoutSec 5
    Write-Host "  Backend responding on that address (mongo: $($health.mongo), live: $($health.changeStreams))" -ForegroundColor Green
} catch {
    Write-Warning "Nothing answered at $base/api/health."
    Write-Warning 'Start it with:  cd backend; npm start'
    Write-Warning 'Building anyway — the address is still correct once it is running.'
}
Write-Host ''

# --- build -----------------------------------------------------------------
# One Flutter command at a time. Two at once deadlock on the tool lockfile and
# sit at 0% CPU forever with no error (CLAUDE.md).
Push-Location $appDir
try {
    Write-Host '  Building split-per-ABI…' -ForegroundColor Cyan
    flutter build apk --release --split-per-abi "--dart-define=GWD_API_BASE=$base"
    if ($LASTEXITCODE -ne 0) { throw 'Split build failed.' }

    if ($Universal) {
        Write-Host '  Building universal…' -ForegroundColor Cyan
        flutter build apk --release "--dart-define=GWD_API_BASE=$base"
        if ($LASTEXITCODE -ne 0) { throw 'Universal build failed.' }
    }
} finally {
    Pop-Location
}

# --- stage -----------------------------------------------------------------
$version = (Select-String -Path (Join-Path $appDir 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$outputs = Join-Path $appDir 'build\app\outputs\flutter-apk'

Copy-Item (Join-Path $outputs 'app-arm64-v8a-release.apk') (Join-Path $projectRoot "GWD-Club-v$version-arm64.apk") -Force
if ($Universal) {
    Copy-Item (Join-Path $outputs 'app-release.apk') (Join-Path $projectRoot "GWD-Club-v$version.apk") -Force
}

# Record what was baked in, so `start-server.ps1` can tell the difference
# between "the server is down" and "the server moved and every installed APK is
# now pointing at the wrong address" — which look identical from the phone.
Set-Content -Path (Join-Path $projectRoot '.last-build-ip') -Value $Ip -Encoding ascii

Write-Host ''
Write-Host ('=' * 64)
Get-ChildItem (Join-Path $projectRoot '*.apk') | ForEach-Object {
    Write-Host ('  {0,7:N1} MB  {1}' -f ($_.Length / 1MB), $_.Name)
}
Write-Host ''
Write-Host "  These reach the backend at $base"
Write-Host '  If the IP changes later, use the server-address override on the'
Write-Host '  sign-in screen rather than rebuilding.'
Write-Host ('=' * 64)
Write-Host ''
