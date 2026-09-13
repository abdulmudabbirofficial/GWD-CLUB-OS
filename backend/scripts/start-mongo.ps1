# Starts a local MongoDB as a SINGLE-NODE REPLICA SET.
#
# Why a replica set for local development: MongoDB Change Streams are built on
# the oplog, and a standalone mongod does not have one. Without this, live sync
# silently does nothing. A one-node replica set gives us a real oplog with none
# of the operational weight of a true cluster.
#
# Safe to re-run: it initiates the set only on first use.

$ErrorActionPreference = 'Stop'

$mongoHome = $env:GWD_MONGO_HOME
if (-not $mongoHome) { $mongoHome = 'D:\dev\gwd-toolchain\mongodb' }
$mongod  = Join-Path $mongoHome 'bin\mongod.exe'
$mongosh = 'D:\dev\gwd-toolchain\mongosh\bin\mongosh.exe'

$dataDir = Join-Path $PSScriptRoot '..\.mongo-data'
$logDir  = Join-Path $PSScriptRoot '..\.mongo-data\log'
New-Item -ItemType Directory -Force -Path $dataDir, $logDir | Out-Null

if (-not (Test-Path $mongod)) {
  Write-Error "mongod not found at $mongod. Set GWD_MONGO_HOME to your MongoDB folder."
}

# Port 27018, never 27017. This machine already runs a MongoDB Windows service
# on the default port and that one is deliberately left alone.
$port = 27018
$uri  = "mongodb://127.0.0.1:$port/?directConnection=true"

# Test the PORT, not the process name. `Get-Process mongod` also matches the
# unrelated Windows service, so the old name check concluded "already running"
# every single time and this script could never actually start our instance.
$listening = $null -ne (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
if ($listening) {
  Write-Host "mongod already listening on $port." -ForegroundColor Yellow
} else {
  Write-Host "Starting mongod with --replSet rs0 on $port ..." -ForegroundColor Cyan
  Start-Process -FilePath $mongod `
    -ArgumentList @('--dbpath', "`"$((Resolve-Path $dataDir).Path)`"", '--replSet', 'rs0', '--bind_ip', '127.0.0.1', '--port', "$port") `
    -WindowStyle Hidden

  # Wait for the socket rather than sleeping a fixed guess: a cold start after
  # an unclean shutdown replays the journal and can take far longer than 4s.
  $ready = $false
  foreach ($i in 1..30) {
    Start-Sleep -Seconds 1
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) { $ready = $true; break }
  }
  if (-not $ready) { Write-Error "mongod did not start listening on $port. Check $logDir." }
}

# Initiate the replica set once. Re-running is harmless.
if (Test-Path $mongosh) {
  $js = "try { rs.status().ok } catch (e) { rs.initiate({_id:'rs0',members:[{_id:0,host:'127.0.0.1:$port'}]}); }"
  & $mongosh --quiet --eval $js $uri | Out-Null

  # Election takes a moment even for a single node; poll for PRIMARY instead of
  # sleeping, or the backend can connect before there is anything to elect.
  $state = 0
  foreach ($i in 1..20) {
    Start-Sleep -Seconds 1
    $state = (& $mongosh --quiet --eval 'rs.status().myState' $uri) -as [int]
    if ($state -eq 1) { break }
  }
  Write-Host "Replica set state: $state  (1 = PRIMARY, ready for Change Streams)" `
    -ForegroundColor $(if ($state -eq 1) { 'Green' } else { 'Red' })
} else {
  Write-Host "mongosh not found - start the replica set manually if this is a fresh data dir." -ForegroundColor Yellow
}
