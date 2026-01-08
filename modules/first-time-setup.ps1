<#
.SYNOPSIS
    First-time setup wizard for git-sum
    
.DESCRIPTION
    Guides users through initial configuration including folder selection and autostart setup.
#>

function Invoke-FirstTimeSetup {
    <#
    .SYNOPSIS
        Runs the first-time setup wizard
    .RETURNS
        True if setup completed, False if cancelled
    #>
    
    Write-Host "[*] First-Time Setup" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "git-sum scans directories containing git repositories and helps"
    Write-Host "keep them all up to date. Let's add some folders to watch."
    Write-Host ""
    
    # Check for updates first
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
    
    if ($updateAvailable) {
        Write-Host "[i] Update available! Run 'git-sum -u' to update after setup." -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Add folders
    $foldersAdded = Invoke-AddFolders
    
    if (-not $foldersAdded) {
        Write-Host ""
        Write-Host "[!] No folders were added. Run 'git-sum -a' later to add folders." -ForegroundColor Yellow
        return $false
    }
    
    # Ask about autostart
    Write-Host ""
    Write-Host "[*] Autostart Configuration" -ForegroundColor Cyan
    Write-Host "--------------------------" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Would you like git-sum to run automatically when you log in?"
    Write-Host "This helps ensure your repos are always up to date."
    Write-Host ""
    
    $autostart = Read-Host "Enable autostart? (y/N)"
    
    if ($autostart -eq "y" -or $autostart -eq "Y") {
        $config = Get-WatchedFolders
        $config.settings.autostart = $true
        Save-WatchedFolders -Config $config
        Install-Autostart
        Write-Host "[OK] Autostart enabled!" -ForegroundColor Green
    } else {
        Write-Host "[i] Autostart not enabled. You can enable it later with 'git-sum -as'" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "[OK] Setup complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run:" -ForegroundColor Yellow
    Write-Host "   git-sum          - Check all repos and pull if safe"
    Write-Host "   git-sum -s       - Show status without pulling"
    Write-Host "   git-sum -a       - Add more folders"
    Write-Host "   git-sum -h       - Show help"
    Write-Host ""
    
    return $true
}

function Invoke-AddFolders {
    <#
    .SYNOPSIS
        Interactive folder addition using native file picker
    .PARAMETER SingleFolder
        If true, only add one folder then return
    .RETURNS
        True if at least one folder was added
    #>
    param(
        [switch]$SingleFolder
    )
    
    $foldersAdded = 0
    
    Write-Host ""
    Write-Host "[>] Add Folders to Watch" -ForegroundColor Cyan
    Write-Host "-----------------------" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select folders that CONTAIN git repositories."
    Write-Host "(e.g., 'C:\Projects' if you have repos like 'C:\Projects\my-repo')"
    Write-Host ""
    
    $continue = $true
    while ($continue) {
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "   1) Browse for folder (opens File Explorer)"
        Write-Host "   2) Enter path manually"
        Write-Host "   q) Done adding folders"
        Write-Host ""
        
        $choice = Read-Host "Choose option"
        
        switch ($choice.ToLower()) {
            "1" {
                $folder = Select-FolderDialog
                if ($folder) {
                    if (Add-WatchedFolder -FolderPath $folder) {
                        $foldersAdded++
                        Show-FolderPreview -FolderPath $folder
                    }
                } else {
                    Write-Host "[i] No folder selected." -ForegroundColor Gray
                }
            }
            "2" {
                $path = Read-Host "Enter folder path"
                if ($path) {
                    $expandedPath = [Environment]::ExpandEnvironmentVariables($path)
                    if (Add-WatchedFolder -FolderPath $expandedPath) {
                        $foldersAdded++
                        Show-FolderPreview -FolderPath $expandedPath
                    }
                }
            }
            "q" {
                $continue = $false
            }
            default {
                Write-Host "Invalid choice." -ForegroundColor Red
            }
        }
        
        if ($SingleFolder -and $foldersAdded -gt 0) {
            $continue = $false
        }
    }
    
    return ($foldersAdded -gt 0)
}

function Select-FolderDialog {
    <#
    .SYNOPSIS
        Opens native Windows folder picker dialog in a separate process to prevent hangs
    .RETURNS
        Selected folder path or $null if cancelled
    #>
    
    Write-Host "[i] Launching folder picker... (check your taskbar if it doesn't appear)" -ForegroundColor Gray
    
    try {
        # Run in a separate process to avoid threading/apartment state issues in the main terminal
        # Ensure we only get the path back by using Out-String and Trim
        $code = "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null; " +
                "`$obj = New-Object System.Windows.Forms.FolderBrowserDialog; " +
                "`$obj.Description = 'Select a folder containing git repositories'; " +
                "`$obj.ShowNewFolderButton = `$false; " +
                "if(`$obj.ShowDialog() -eq 'OK') { Write-Output `$obj.SelectedPath }"
        
        # Use -NoLogo and -NoProfile to minimize noise
        $result = powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $code
        
        if ($result) {
            # Capture only the last line if multiple lines returned
            if ($result -is [array]) {
                $path = [string]($result[-1])
            } else {
                $path = [string]$result
            }
            
            $path = $path.Trim()
            if ($path -and (Test-Path $path)) {
                return $path
            }
        }
    } catch {
        Write-Host "[!] Error opening folder picker: $_" -ForegroundColor Yellow
    }
    
    return $null
}

function Show-FolderPreview {
    <#
    .SYNOPSIS
        Shows a preview of git repos found in a folder
    .PARAMETER FolderPath
        The folder to preview
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderPath
    )
    
    Write-Host ""
    Write-Host "   Found repositories:" -ForegroundColor Gray
    
    $subDirs = Get-ChildItem -Path $FolderPath -Directory -ErrorAction SilentlyContinue
    $repoCount = 0
    $maxShow = 5
    
    foreach ($subDir in $subDirs) {
        if (Test-Path (Join-Path $subDir.FullName ".git")) {
            $repoCount++
            if ($repoCount -le $maxShow) {
                Write-Host "      [*] $($subDir.Name)" -ForegroundColor Gray
            }
        }
    }
    
    if ($repoCount -gt $maxShow) {
        Write-Host "      ... and $($repoCount - $maxShow) more" -ForegroundColor Gray
    }
    
    if ($repoCount -eq 0) {
        Write-Host "      (no git repositories found in first level)" -ForegroundColor Yellow
    } else {
        Write-Host "      Total: $repoCount repositories" -ForegroundColor Green
    }
}
