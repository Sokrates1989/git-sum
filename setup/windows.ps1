<#
.SYNOPSIS
    Windows setup script for git-sum
    
.DESCRIPTION
    Downloads and installs git-sum, creates global command, and runs first-time setup.
    
.NOTES
    Run in PowerShell (Administrator recommended for best results)
#>

$ErrorActionPreference = "Stop"

$TargetDir = "$env:USERPROFILE\tools\git-sum"
$RepoUrl = "https://github.com/Sokrates1989/git-sum.git"

Write-Host ""
Write-Host "[*] git-sum Installer" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Installing git-sum into $TargetDir" -ForegroundColor Cyan

# Step 1: Clone or update the repository
if (-not (Test-Path "$TargetDir\.git")) {
    Write-Host "Cloning repository..." -ForegroundColor Yellow
    
    # Remove existing directory if it exists but is not a git repo
    if (Test-Path $TargetDir) {
        Write-Host "Removing incomplete installation..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $TargetDir -ErrorAction SilentlyContinue
    }
    
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Push-Location $TargetDir
    git clone $RepoUrl .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to clone repository." -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
} else {
    Write-Host "[INFO] git-sum already cloned - attempting to update..." -ForegroundColor Yellow
    Push-Location $TargetDir
    git pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Could not fast-forward; continuing with existing clone." -ForegroundColor Yellow
    }
    Pop-Location
}

# Step 2: Run the installer
Write-Host "[INFO] Running installer..." -ForegroundColor Cyan
Push-Location $TargetDir
& .\install.ps1
Pop-Location

Write-Host ""
Write-Host "[OK] Installation complete!" -ForegroundColor Green
