#requires -Version 5.1
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "Sending SIGINT so ros_main_controller attempts CM530 STOP..."
docker kill --signal SIGINT phantomx-puzzle-controller 2>$null | Out-Null
Start-Sleep -Seconds 2

Push-Location $Root
docker compose -f compose.yaml -f compose.windows-hardware.yaml --profile hardware down --remove-orphans
Pop-Location
Write-Host "Windows stack stopped. Verify the physical arm is stationary before touching it."

