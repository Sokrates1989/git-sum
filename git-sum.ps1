<#
.SYNOPSIS
    git-sum - Git Repository Status Summary Tool for Windows PowerShell
    
.DESCRIPTION
    Scans configured directories for git repositories and provides a summary of their states.
    Automatically pulls changes when safe, and offers solutions for repos with issues.
    
.PARAMETER Add
    Add more folders to watch (alias: -a)
    
.PARAMETER Status
    Dry run - show status without pulling (alias: -s)
    
.PARAMETER Config
    Open configuration editor (alias: -c)
    
.PARAMETER Autostart
    Configure autostart settings (alias: -as)
    
.PARAMETER Update
    Update git-sum to latest version (alias: -u)
    
.PARAMETER Help
    Show help message (alias: -h)

.EXAMPLE
    git-sum              # Normal run - check all repos and pull if safe
    git-sum -a           # Add more folders to watch
    git-sum --status     # Dry run - show status without pulling
    git-sum --help       # Show help

.NOTES
    Author: Sokrates1989
    Version: 1.0.0
#>

param(
    [Alias("a")][switch]$Add,
    [Alias("s")][switch]$Status,
    [Alias("c")][switch]$Config,
    [Alias("as")][switch]$Autostart,
    [Alias("u")][switch]$Update,
    [Alias("h")][switch]$Help
)

$ErrorActionPreference = "Stop"

# === Script paths ===
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Resolve-Path "$ScriptDir" | Select-Object -ExpandProperty Path
$ConfigDir = Join-Path $RootDir "config"
$ConfigFile = Join-Path $ConfigDir "watched-folders.json"
$ModulesDir = Join-Path $RootDir "modules"

# === Unblock all .ps1 files ===
Get-ChildItem -Path "$RootDir" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -Path $_.FullName } catch { }
}

# === Import modules ===
. "$ModulesDir\config-manager.ps1"
. "$ModulesDir\git-operations.ps1"
. "$ModulesDir\first-time-setup.ps1"
. "$ModulesDir\ui-helpers.ps1"
. "$ModulesDir\autostart-manager.ps1"

# === Helper Functions ===

function Show-Help {
    <#
    .SYNOPSIS
        Displays help information for git-sum
    #>
    Write-Host ""
    Write-Host "[*] git-sum - Git Repository Status Summary Tool" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  git-sum              Normal run - check all repos and pull if safe"
    Write-Host "  git-sum -a           Add more folders to watch (--add)"
    Write-Host "  git-sum -s           Dry run - show status without pulling (--status)"
    Write-Host "  git-sum -c           Open configuration editor (--config)"
    Write-Host "  git-sum -as          Configure autostart settings (--autostart)"
    Write-Host "  git-sum -u           Update to latest version (--update)"
    Write-Host "  git-sum -h           Show this help (--help)"
    Write-Host ""
    Write-Host "Description:" -ForegroundColor Yellow
    Write-Host "  Scans configured directories for git repositories and provides"
    Write-Host "  a summary of their states. Automatically pulls changes when safe,"
    Write-Host "  and offers solutions for repos that need attention."
    Write-Host ""
}

function Test-FirstTimeSetup {
    <#
    .SYNOPSIS
        Checks if first-time setup is needed and runs it if necessary
    .RETURNS
        True if setup was completed or not needed, False if user cancelled
    #>
    if (-not (Test-Path $ConfigFile)) {
        Write-Host ""
        Write-Host "[*] Welcome to git-sum!" -ForegroundColor Cyan
        Write-Host "   It looks like this is your first time running git-sum." -ForegroundColor Gray
        Write-Host ""
        return Invoke-FirstTimeSetup
    }
    
    $config = Get-WatchedFolders
    if ($config.folders.Count -eq 0) {
        Write-Host ""
        Write-Host "[!] No folders configured yet." -ForegroundColor Yellow
        Write-Host ""
        return Invoke-FirstTimeSetup
    }
    
    return $true
}

function Invoke-Update {
    <#
    .SYNOPSIS
        Updates git-sum to the latest version
    #>
    Write-Host ""
    Write-Host "[*] Checking for updates..." -ForegroundColor Cyan
    
    Push-Location $RootDir
    try {
        $statusLines = Run-GitCommand -Arguments "status", "--porcelain" -WorkingDirectory $RootDir
        if ($statusLines) {
            Write-Host "[!] Local changes detected. Please commit or stash them first." -ForegroundColor Yellow
            return
        }
        
        Run-GitCommand -Arguments "fetch", "origin" -WorkingDirectory $RootDir
        $behindLines = Run-GitCommand -Arguments "rev-list", "--count", "HEAD..origin/main" -WorkingDirectory $RootDir
        $behind = 0
        $behindStr = ($behindLines | Select-Object -First 1)
        if ($behindStr -and $behindStr.ToString().Trim() -match "^\d+$") { $behind = [int]$behindStr }
        
        if ($behind -gt 0) {
            Write-Host "[>] Updating git-sum ($($behind) commits behind)..." -ForegroundColor Yellow
            Run-GitCommand -Arguments "pull", "--ff-only" -WorkingDirectory $RootDir
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Updated successfully!" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] Pull failed during update." -ForegroundColor Red
            }
        } else {
            Write-Host "[OK] Already up to date." -ForegroundColor Green
        }
    } catch {
        Write-Host "[ERROR] Update failed: $_" -ForegroundColor Red
    } finally {
        Pop-Location
    }
}

# === Main Logic ===

if ($Help) {
    Show-Help
    exit 0
}

if ($Update) {
    Invoke-Update
    exit 0
}

# Check for updates (non-intrusive)
$updateAvailable = $false
try {
    $null = Run-GitCommand -Arguments "fetch", "--quiet", "origin" -TimeoutSeconds 10 -WorkingDirectory $RootDir
    if ($LASTEXITCODE -eq 0) {
        $null = Run-GitCommand -Arguments "diff", "--quiet", "HEAD..origin/HEAD" -TimeoutSeconds 10 -WorkingDirectory $RootDir
        if ($LASTEXITCODE -eq 1) {
            $updateAvailable = $true
        }
    }
} catch {
    # Ignore update check failures
}

# Ensure config directory exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

if ($Add) {
    # Add more folders mode
    if (-not (Test-FirstTimeSetup)) {
        exit 0
    }
    Invoke-AddFolders
    exit 0
}

if ($Config) {
    # Config editor mode
    Invoke-ConfigEditor
    exit 0
}

if ($Autostart) {
    # Autostart configuration mode
    Invoke-AutostartConfig
    exit 0
}

# Check for first-time setup
if (-not (Test-FirstTimeSetup)) {
    exit 0
}

# Normal run or status mode
$dryRun = $Status.IsPresent

# Show update notification first, before any scanning
if ($updateAvailable) {
    Write-Host ""
    Write-Host "[*] git-sum - Git Repository Status Summary" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[i] Update available! Run 'git-sum -u' to update." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "[*] git-sum - Git Repository Status Summary" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[i] git-sum is up to date." -ForegroundColor Green
    Write-Host ""
}

Write-Host ""
Write-Host "[*] git-sum - Scanning repositories..." -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

if ($dryRun) {
    Write-Host "   (Dry run mode - no changes will be made)" -ForegroundColor Yellow
}

Write-Host ""

# Get all repos and check their status
$results = Invoke-RepoScan -DryRun:$dryRun

# Display summary
Show-Summary -Results $results -DryRun:$dryRun
