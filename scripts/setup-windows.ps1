#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipPackageInstall
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage([string]$Id) {
    $installed = winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $installed -match [regex]::Escape($Id)) {
        Write-Host "[ok] $Id"
        return
    }
    Write-Host "[install] $Id"
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install $Id"
    }
}

function Install-GitHubCliMsi {
    $version = "2.100.0"
    $expectedSha256 = "989cdda347f142cfa33c4457be5fec6c2e283a9a65525ade49a36d2a6cddb276"
    $uri = "https://github.com/cli/cli/releases/download/v$version/gh_${version}_windows_amd64.msi"
    $msi = Join-Path $env:TEMP "gh_${version}_windows_amd64.msi"
    Invoke-WebRequest -Uri $uri -OutFile $msi -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expectedSha256) { throw "GitHub CLI MSI checksum mismatch." }
    $signature = Get-AuthenticodeSignature -LiteralPath $msi
    if ($signature.Status -ne "Valid") { throw "GitHub CLI MSI signature is not valid." }
    $process = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "GitHub CLI MSI installation failed: $($process.ExitCode)" }
}

Write-Host "Checking Windows deployment prerequisites..."
if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Windows deployment requires x86_64/AMD64 Windows."
}

if (-not $SkipPackageInstall) {
    if (-not (Test-Command "winget")) {
        if (-not (Test-Command "gh")) { Install-GitHubCliMsi }
        foreach ($required in @("git", "docker", "usbipd")) {
            if (-not (Test-Command $required)) {
                throw "winget is unavailable and $required is missing. Install Microsoft App Installer, then rerun."
            }
        }
    } else {
        Install-WingetPackage "Git.Git"
        Install-WingetPackage "GitHub.cli"
        Install-WingetPackage "Docker.DockerDesktop"
        Install-WingetPackage "dorssel.usbipd-win"
    }
}

wsl.exe --status | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "WSL2 is not ready. Run 'wsl --install --no-distribution' as Administrator and reboot."
}

if (-not (Test-Path (Join-Path $Root ".env"))) {
    Copy-Item (Join-Path $Root ".env.example") (Join-Path $Root ".env")
    Write-Host "Created .env from .env.example."
}

$dockerSettings = Join-Path $env:APPDATA "Docker\settings-store.json"
if (Test-Path $dockerSettings) {
    $settings = Get-Content -LiteralPath $dockerSettings -Raw | ConvertFrom-Json
    if ($null -eq $settings.EnableHostNetworking -or -not $settings.EnableHostNetworking) {
        Copy-Item -LiteralPath $dockerSettings -Destination "$dockerSettings.phantomx-backup" -Force
        $settings | Add-Member -NotePropertyName EnableHostNetworking -NotePropertyValue $true -Force
        $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $dockerSettings -Encoding utf8
        Write-Host "Enabled Docker Desktop host networking. Restart Docker Desktop before tests."
    }
}

if (Test-Path (Join-Path $Root ".git")) {
    git -C $Root submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to initialize repository components."
    }
}

Write-Host "Setup check complete. No camera or robot command was sent."
Write-Host "Start simulation with: .\scripts\test-windows-sim.ps1"
