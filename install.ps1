<#
.SYNOPSIS
    Windows installer for git-sum
    
.DESCRIPTION
    Creates global 'git-sum' command and optionally runs first-time setup.
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GitSumScript = Join-Path $ScriptDir "git-sum.ps1"

Write-Host ""
Write-Host "🔄 git-sum Installer" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Installing git-sum..." -ForegroundColor Cyan

# Step 1: Unblock all scripts
Write-Host "Unblocking PowerShell scripts..." -ForegroundColor Yellow
Get-ChildItem -Path "$ScriptDir" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -Path $_.FullName } catch { }
}

# Step 2: Ensure config directory exists
$ConfigDir = Join-Path $ScriptDir "config"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# Step 3: Add global 'git-sum' command to PowerShell profile
$ProfileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

$AliasLine = "Set-Alias git-sum `"$GitSumScript`""
$ProfileExists = Test-Path $PROFILE
$AliasExists = $false

if ($ProfileExists) {
    $ProfileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($ProfileContent -match "git-sum") {
        $AliasExists = $true
    }
}

if (-not $AliasExists) {
    Write-Host ""
    Write-Host "To use 'git-sum' command globally, we need to add an alias to your PowerShell profile." -ForegroundColor Cyan
    $AddAlias = Read-Host "Add 'git-sum' command to PowerShell profile? (Y/n)"
    if ($AddAlias -ne "n" -and $AddAlias -ne "N") {
        # Add alias to profile
        Add-Content -Path $PROFILE -Value ""
        Add-Content -Path $PROFILE -Value "# git-sum - Git Repository Status Summary"
        Add-Content -Path $PROFILE -Value $AliasLine
        Write-Host "✅ Added 'git-sum' alias to PowerShell profile." -ForegroundColor Green
        Write-Host "   Restart your terminal or run: . `$PROFILE" -ForegroundColor Yellow
    } else {
        Write-Host "ℹ️  Skipped adding alias. You can run git-sum directly:" -ForegroundColor Gray
        Write-Host "   $GitSumScript" -ForegroundColor Gray
    }
} else {
    Write-Host "✅ 'git-sum' alias already exists in PowerShell profile." -ForegroundColor Green
}

# Step 4: Create Desktop shortcut (optional)
Write-Host ""
$CreateShortcut = Read-Host "Create Desktop shortcut? (y/N)"
if ($CreateShortcut -eq "y" -or $CreateShortcut -eq "Y") {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $DesktopPath "git-sum.lnk"
    
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File `"$GitSumScript`""
        $Shortcut.WorkingDirectory = $ScriptDir
        $Shortcut.Description = "git-sum - Git Repository Status Summary"
        $Shortcut.Save()
        Write-Host "✅ Created Desktop shortcut: git-sum.lnk" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not create Desktop shortcut: $_" -ForegroundColor Yellow
    }
}

# Step 5: Add to CMD path (optional)
Write-Host ""
Write-Host "To use 'git-sum' in CMD (Command Prompt), the script directory needs to be in PATH." -ForegroundColor Cyan
$AddToPath = Read-Host "Add git-sum to system PATH for CMD access? (y/N)"
if ($AddToPath -eq "y" -or $AddToPath -eq "Y") {
    # Create a batch wrapper
    $BatchWrapper = Join-Path $ScriptDir "git-sum.cmd"
    $BatchContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0git-sum.ps1" %*
"@
    Set-Content -Path $BatchWrapper -Value $BatchContent -Encoding ASCII
    
    # Add to user PATH
    $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($CurrentPath -notlike "*$ScriptDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$CurrentPath;$ScriptDir", "User")
        Write-Host "✅ Added git-sum to user PATH." -ForegroundColor Green
        Write-Host "   Restart your terminal for changes to take effect." -ForegroundColor Yellow
    } else {
        Write-Host "ℹ️  git-sum directory already in PATH." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "✅ Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Usage (after restarting terminal):" -ForegroundColor White
Write-Host "  git-sum           - Check all repos and pull if safe" -ForegroundColor Gray
Write-Host "  git-sum -s        - Show status without pulling (dry run)" -ForegroundColor Gray
Write-Host "  git-sum -a        - Add more folders to watch" -ForegroundColor Gray
Write-Host "  git-sum -c        - Open configuration editor" -ForegroundColor Gray
Write-Host "  git-sum -h        - Show help" -ForegroundColor Gray
Write-Host ""
Write-Host "First run will guide you through initial setup." -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan
