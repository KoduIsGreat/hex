# Build and run the hex game (Odin + Karl2D).
#
# From PowerShell:  .\run.ps1
# From cmd:         run.bat
$ErrorActionPreference = "Stop"

$gameDir = Join-Path $PSScriptRoot "game"
if (-not (Test-Path $gameDir)) {
    Write-Error "Game directory not found: $gameDir"
    exit 1
}

Push-Location $gameDir
try {
    odin run .
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
