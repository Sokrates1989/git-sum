<#
.SYNOPSIS
    Autostart management for git-sum
    
.DESCRIPTION
    Handles Windows startup configuration for git-sum.
#>

function Install-Autostart {
    <#
    .SYNOPSIS
        Installs git-sum to Windows startup
    #>
    
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $shortcutPath = Join-Path $startupFolder "git-sum.lnk"
    $targetScript = Join-Path $RootDir "git-sum.ps1"
    
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Normal -File `"$targetScript`""
        $Shortcut.WorkingDirectory = $RootDir
        $Shortcut.Description = "git-sum - Git Repository Status Summary"
        $Shortcut.Save()
        
        Write-Host "[OK] Added git-sum to Windows startup" -ForegroundColor Green
        Write-Host "   Location: $shortcutPath" -ForegroundColor Gray
        return $true
    } catch {
        Write-Host "[X] Failed to add autostart: $_" -ForegroundColor Red
        return $false
    }
}

function Uninstall-Autostart {
    <#
    .SYNOPSIS
        Removes git-sum from Windows startup
    #>
    
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $shortcutPath = Join-Path $startupFolder "git-sum.lnk"
    
    if (Test-Path $shortcutPath) {
        try {
            Remove-Item $shortcutPath -Force
            Write-Host "[OK] Removed git-sum from Windows startup" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "[X] Failed to remove autostart: $_" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "[i] git-sum was not in startup" -ForegroundColor Gray
        return $true
    }
}

function Test-AutostartInstalled {
    <#
    .SYNOPSIS
        Checks if git-sum is in Windows startup
    .RETURNS
        True if installed, False otherwise
    #>
    
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $shortcutPath = Join-Path $startupFolder "git-sum.lnk"
    
    return (Test-Path $shortcutPath)
}

function Invoke-AutostartConfig {
    <#
    .SYNOPSIS
        Interactive autostart configuration
    #>
    
    $isInstalled = Test-AutostartInstalled
    $config = Get-WatchedFolders
    
    Write-Host ""
    Write-Host "[*] Autostart Configuration" -ForegroundColor Cyan
    Write-Host "==========================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($isInstalled) {
        Write-Host "   Status: [OK] Enabled" -ForegroundColor Green
        Write-Host "   git-sum will run when you log in to Windows." -ForegroundColor Gray
    } else {
        Write-Host "   Status: [X] Disabled" -ForegroundColor Yellow
        Write-Host "   git-sum will not run automatically." -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    
    if ($isInstalled) {
        Write-Host "   1) Disable autostart"
    } else {
        Write-Host "   1) Enable autostart"
    }
    Write-Host "   q) Back"
    Write-Host ""
    
    $choice = Read-Host "Choose option"
    
    switch ($choice.ToLower()) {
        "1" {
            if ($isInstalled) {
                $config.settings.autostart = $false
                Save-WatchedFolders -Config $config
                Uninstall-Autostart
            } else {
                $config.settings.autostart = $true
                Save-WatchedFolders -Config $config
                Install-Autostart
            }
        }
        "q" {
            return
        }
        default {
            Write-Host "Invalid choice." -ForegroundColor Red
        }
    }
}
