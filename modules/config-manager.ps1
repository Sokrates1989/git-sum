<#
.SYNOPSIS
    Configuration management for git-sum
    
.DESCRIPTION
    Handles reading, writing, and managing the watched folders configuration.
#>

function Get-WatchedFolders {
    <#
    .SYNOPSIS
        Reads the watched folders configuration from disk
    .RETURNS
        Hashtable with 'folders' array and optional settings
    #>
    $ConfigFile = Join-Path (Join-Path $RootDir "config") "watched-folders.json"
    
    if (-not (Test-Path $ConfigFile)) {
        return @{
            folders = @()
            settings = @{
                autostart = $false
                lastRun = $null
            }
        }
    }
    
    try {
        $content = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        
        # Convert to hashtable for easier manipulation
        $config = @{
            folders = @()
            settings = @{
                autostart = $false
                lastRun = $null
            }
        }
        
        if ($content.folders) {
            $config.folders = @($content.folders)
        }
        
        if ($content.settings) {
            if ($null -ne $content.settings.autostart) {
                $config.settings.autostart = $content.settings.autostart
            }
            if ($content.settings.lastRun) {
                $config.settings.lastRun = $content.settings.lastRun
            }
        }
        
        return $config
    } catch {
        Write-Host "[!] Error reading config: $_" -ForegroundColor Yellow
        return @{
            folders = @()
            settings = @{
                autostart = $false
                lastRun = $null
            }
        }
    }
}

function Save-WatchedFolders {
    <#
    .SYNOPSIS
        Saves the watched folders configuration to disk
    .PARAMETER Config
        The configuration hashtable to save
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )
    
    $ConfigDir = Join-Path $RootDir "config"
    $ConfigFile = Join-Path $ConfigDir "watched-folders.json"
    
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    
    # Update last run timestamp
    $Config.settings.lastRun = (Get-Date).ToString("o")
    
    $Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8
}

function Add-WatchedFolder {
    <#
    .SYNOPSIS
        Adds a folder to the watched folders list
    .PARAMETER FolderPath
        The path to add
    .RETURNS
        True if added, False if already exists or invalid
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderPath
    )
    
    if (-not (Test-Path $FolderPath)) {
        Write-Host "[X] Folder does not exist: $FolderPath" -ForegroundColor Red
        return $false
    }
    
    $config = Get-WatchedFolders
    
    # Normalize path
    $normalizedPath = (Resolve-Path $FolderPath).Path
    
    # Check if already exists
    if ($config.folders -contains $normalizedPath) {
        Write-Host "[i] Folder already in watch list: $normalizedPath" -ForegroundColor Yellow
        return $false
    }
    
    $config.folders += $normalizedPath
    Save-WatchedFolders -Config $config
    
    Write-Host "[OK] Added folder: $normalizedPath" -ForegroundColor Green
    return $true
}

function Remove-WatchedFolder {
    <#
    .SYNOPSIS
        Removes a folder from the watched folders list
    .PARAMETER FolderPath
        The path to remove
    .RETURNS
        True if removed, False if not found
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderPath
    )
    
    $config = Get-WatchedFolders
    
    # Normalize path
    $resolved = Resolve-Path $FolderPath -ErrorAction SilentlyContinue
    if ($resolved) {
        $normalizedPath = $resolved.Path
    } else {
        $normalizedPath = $FolderPath
    }
    
    $newFolders = @($config.folders | Where-Object { $_ -ne $normalizedPath -and $_ -ne $FolderPath })
    
    if ($newFolders.Count -eq $config.folders.Count) {
        Write-Host "[i] Folder not in watch list: $FolderPath" -ForegroundColor Yellow
        return $false
    }
    
    $config.folders = $newFolders
    Save-WatchedFolders -Config $config
    
    Write-Host "[OK] Removed folder: $FolderPath" -ForegroundColor Green
    return $true
}

function Invoke-ConfigEditor {
    <#
    .SYNOPSIS
        Interactive configuration editor
    #>
    $config = Get-WatchedFolders
    
    while ($true) {
        Write-Host ""
        Write-Host "[*] git-sum Configuration" -ForegroundColor Cyan
        Write-Host "=========================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Current watched folders:" -ForegroundColor Yellow
        
        if ($config.folders.Count -eq 0) {
            Write-Host "   (none)" -ForegroundColor Gray
        } else {
            $index = 1
            foreach ($folder in $config.folders) {
                $exists = Test-Path $folder
                $status = if ($exists) { "[OK]" } else { "[X] (not found)" }
                Write-Host "   $index) $folder $status"
                $index++
            }
        }
        
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "   a) Add folder"
        Write-Host "   r) Remove folder"
        Write-Host "   s) Toggle autostart (currently: $(if ($config.settings.autostart) { 'ON' } else { 'OFF' }))"
        Write-Host "   q) Back to main"
        Write-Host ""
        
        $choice = Read-Host "Enter choice"
        
        switch ($choice.ToLower()) {
            "a" {
                Invoke-AddFolders -SingleFolder
                $config = Get-WatchedFolders
            }
            "r" {
                if ($config.folders.Count -eq 0) {
                    Write-Host "No folders to remove." -ForegroundColor Yellow
                } else {
                    $removeIndex = Read-Host "Enter folder number to remove (or 'c' to cancel)"
                    if ($removeIndex -ne "c") {
                        $idx = [int]$removeIndex - 1
                        if ($idx -ge 0 -and $idx -lt $config.folders.Count) {
                            Remove-WatchedFolder -FolderPath $config.folders[$idx]
                            $config = Get-WatchedFolders
                        } else {
                            Write-Host "Invalid selection." -ForegroundColor Red
                        }
                    }
                }
            }
            "s" {
                $config.settings.autostart = -not $config.settings.autostart
                Save-WatchedFolders -Config $config
                if ($config.settings.autostart) {
                    Install-Autostart
                } else {
                    Uninstall-Autostart
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
}

