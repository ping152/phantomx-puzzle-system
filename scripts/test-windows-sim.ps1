#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$env:DOCKER_PLATFORM = "linux/amd64"
$env:ROS_DOMAIN_ID = if ($env:ROS_DOMAIN_ID) { $env:ROS_DOMAIN_ID } else { "31" }
$env:VISION_MODE = "mock"
$env:ENABLE_RVIZ = if ($env:ENABLE_RVIZ) { $env:ENABLE_RVIZ } else { "true" }

python (Join-Path $PSScriptRoot "deployment_guard.py") | Out-Host
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop is not running."
}

Push-Location $Root
try {
    if (-not $SkipBuild) {
        docker compose --profile test build
        if ($LASTEXITCODE -ne 0) { throw "Image build failed." }
        $motionImage = if ($env:MOTION_IMAGE) { $env:MOTION_IMAGE } else { "ghcr.io/ping152/phantomx-puzzle-motion:v0.1.0-rc1" }
        $visionImage = if ($env:VISION_IMAGE) { $env:VISION_IMAGE } else { "ghcr.io/ping152/phantomx-puzzle-vision:v0.1.0-rc1" }
        $motionArch = docker image inspect $motionImage --format '{{.Architecture}}'
        $visionArch = docker image inspect $visionImage --format '{{.Architecture}}'
        if ($motionArch -ne "amd64" -or $visionArch -ne "amd64") {
            throw "Simulation images are not both linux/amd64."
        }
    }
    docker compose --profile test run --rm controller-tests
    if ($LASTEXITCODE -ne 0) { throw "Controller unit tests failed." }
    docker compose --profile test up -d moveit
    if ($LASTEXITCODE -ne 0) { throw "MoveIt failed to start." }
    docker compose --profile test run --rm multipoint-probe
    if ($LASTEXITCODE -ne 0) { throw "Eight-point MoveIt probe failed." }
} finally {
    docker compose --profile test down --remove-orphans
    Pop-Location
}

Write-Host "Windows amd64 simulation verification passed. No hardware was driven."
