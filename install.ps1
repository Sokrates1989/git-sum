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
Write-Host "[*] git-sum Installer" -ForegroundColor Cyan
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
        Write-Host "[OK] Added 'git-sum' alias to PowerShell profile." -ForegroundColor Green
        Write-Host "   Restart your terminal or run: . `$PROFILE" -ForegroundColor Yellow
    } else {
        Write-Host "[i] Skipped adding alias. You can run git-sum directly:" -ForegroundColor Gray
        Write-Host "   $GitSumScript" -ForegroundColor Gray
    }
} else {
    Write-Host "[OK] 'git-sum' alias already exists in PowerShell profile." -ForegroundColor Green
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
        Write-Host "[OK] Created Desktop shortcut: git-sum.lnk" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not create Desktop shortcut: $_" -ForegroundColor Yellow
    }
}

# Step 5: Add to system PATH
Write-Host ""
Write-Host "Adding git-sum to system PATH for global access..." -ForegroundColor Cyan

# Create a batch wrapper
$BatchWrapper = Join-Path $ScriptDir "git-sum.cmd"
$BatchLines = @(
    "@echo off",
    "powershell.exe -ExecutionPolicy Bypass -File ""%~dp0git-sum.ps1"" %*"
)
$BatchLines | Set-Content -Path $BatchWrapper -Encoding ASCII

# Add to user PATH
try {
    $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($CurrentPath -notlike "*$ScriptDir*") {
            $NewPath = "$CurrentPath;$ScriptDir"
            [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
            Write-Host "[OK] Added git-sum to user PATH." -ForegroundColor Green
        } else {
            Write-Host "[i] git-sum directory already in PATH." -ForegroundColor Gray
        }
    } catch {
        Write-Host "[WARN] Could not update PATH: $_" -ForegroundColor Yellow
    }

# Step 6: Setup autostart (optional)
Write-Host ""
$EnableAutostart = Read-Host "Enable autostart (run git-sum on login)? (y/N)"
if ($EnableAutostart -eq "y" -or $EnableAutostart -eq "Y") {
    try {
        # Source the autostart manager functions
        $AutostartManager = Join-Path $ScriptDir "modules\autostart-manager.ps1"
        if (Test-Path $AutostartManager) {
            . $AutostartManager
            
            if (Install-Autostart) {
                Write-Host "[OK] Autostart enabled - git-sum will run on login" -ForegroundColor Green
            } else {
                Write-Host "[!] Failed to enable autostart" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[!] Autostart manager not found - you can enable it later with: git-sum -as" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Failed to setup autostart: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "[OK] Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Usage:" -ForegroundColor White
Write-Host "  git-sum           - Check all repos and pull if safe" -ForegroundColor Gray
Write-Host "  git-sum -s        - Show status without pulling (dry run)" -ForegroundColor Gray
Write-Host "  git-sum -a        - Add more folders to watch" -ForegroundColor Gray
Write-Host "  git-sum -c        - Open configuration editor" -ForegroundColor Gray
Write-Host "  git-sum -u        - Update to latest version" -ForegroundColor Gray
Write-Host "  git-sum -h        - Show help" -ForegroundColor Gray
Write-Host ""
Write-Host "First run will guide you through initial setup." -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan
