#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SerialDevice = "",
    [int]$CameraIndex = 0
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VisionRoot = Join-Path $Root "components\vision"

$envFile = Join-Path $Root ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $name = $Matches[1]
            if ($null -eq [Environment]::GetEnvironmentVariable($name, "Process")) {
                [Environment]::SetEnvironmentVariable($name, $Matches[2], "Process")
            }
        }
    }
}
if (-not $SerialDevice) {
    $SerialDevice = if ($env:CM530_DEVICE) { $env:CM530_DEVICE } else { "/dev/ttyUSB0" }
}

if ($SerialDevice -notmatch '^/dev/(ttyUSB\d+|ttyACM\d+|phantomx-cm530)$') {
    throw "Unsupported serial device path: $SerialDevice"
}

python (Join-Path $PSScriptRoot "deployment_guard.py") --expect-owner windows --owner $env:HARDWARE_OWNER | Out-Host
if ($env:RELEASE_MODE -eq "1") {
    python (Join-Path $PSScriptRoot "deployment_guard.py") --release-image $env:MOTION_IMAGE --release-image $env:VISION_IMAGE | Out-Host
}

$env:DOCKER_PLATFORM = "linux/amd64"
$env:ROS_DOMAIN_ID = if ($env:ROS_DOMAIN_ID) { $env:ROS_DOMAIN_ID } else { "31" }
$env:CM530_DEVICE = $SerialDevice
$env:CM530_CONTAINER_DEVICE = $SerialDevice
$env:VISION_MODE = "windows"

docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker Desktop is not running." }
if (-not (Get-Command usbipd.exe -ErrorAction SilentlyContinue)) {
    throw "usbipd-win is required. Run setup-windows.ps1 first."
}

wsl.exe -e test -c $SerialDevice
if ($LASTEXITCODE -ne 0) {
    throw "$SerialDevice is not attached to WSL2. Use 'usbipd list', then bind and attach the CM530 USB device."
}

python -c "import cv2; c=cv2.VideoCapture($CameraIndex); ok=c.isOpened(); c.release(); raise SystemExit(0 if ok else 1)"
if ($LASTEXITCODE -ne 0) { throw "Windows camera index $CameraIndex is unavailable." }

$confirmation = Read-Host "Disconnect people/tools from the arm, make STOP reachable, then type HOME to authorize homing"
if ($confirmation -cne "HOME") { throw "HOME authorization was not granted." }

Push-Location $Root
try {
    docker compose -f compose.yaml -f compose.windows-hardware.yaml --profile hardware up -d moveit vision
    if ($LASTEXITCODE -ne 0) { throw "Support services failed to start." }

    $nodes = docker compose -f compose.yaml -f compose.windows-hardware.yaml exec -T moveit bash -lc "ros2 node list" 2>$null
    if ($nodes -match '(^|\s)/ros_main_controller($|\s)') {
        throw "A ros_main_controller is already visible on ROS_DOMAIN_ID=$env:ROS_DOMAIN_ID."
    }

    $sender = Join-Path $VisionRoot "windows_camera_ros_sender.py"
    if (-not (Test-Path $sender)) { throw "Windows camera sender not found: $sender" }
    $senderArgs = "-NoExit -Command Set-Location '$VisionRoot'; python windows_camera_ros_sender.py --index $CameraIndex --host 127.0.0.1 --port 5001 --preview"
    Start-Process powershell.exe -ArgumentList $senderArgs -WindowStyle Normal

    Write-Host "Controller is interactive. Press R to plan and move; press Ctrl+C for STOP and shutdown."
    docker compose -f compose.yaml -f compose.windows-hardware.yaml --profile hardware run --name phantomx-puzzle-controller --rm controller
} finally {
    & (Join-Path $PSScriptRoot "stop-windows.ps1")
    Pop-Location
}
