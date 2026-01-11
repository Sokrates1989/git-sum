<#
.SYNOPSIS
    Git operations for git-sum
    
.DESCRIPTION
    Handles git repository scanning, status checking, and safe pulling.
#>

function Run-GitCommand {
    <#
    .SYNOPSIS
        Runs a git command with environment variables to prevent interactive prompts and a hard timeout.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 20,
        [string]$WorkingDirectory = (Get-Location).Path
    )
    
    $oldPrompt = $env:GIT_TERMINAL_PROMPT
    $oldGcm = $env:GCM_INTERACTIVE
    $oldSsh = $env:GIT_SSH_COMMAND
    
    try {
        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GCM_INTERACTIVE = "never"
        $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes"
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "git"
        $psi.Arguments = $Arguments -join " "
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        
        if (-not $process.Start()) {
            throw "Failed to start git process"
        }
        
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $global:LASTEXITCODE = 124 # Timeout exit code
            return @("Error: Git command timed out after $TimeoutSeconds seconds")
        }
        
        $global:LASTEXITCODE = $process.ExitCode
        
        $output = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        
        $lines = @()
        if ($output) { 
            $splitLines = $output -split "`r?`n" | Where-Object { $_ } | ForEach-Object { $_.ToString() }
            if ($splitLines) { $lines += $splitLines }
        }
        if ($stdErr) { 
            $splitError = $stdErr -split "`r?`n" | Where-Object { $_ } | ForEach-Object { $_.ToString() }
            if ($splitError) { $lines += $splitError }
        }
        
        return $lines
    } catch {
        $global:LASTEXITCODE = 1
        return @("Error: $($_.Exception.Message)")
    } finally {
        $env:GIT_TERMINAL_PROMPT = $oldPrompt
        $env:GCM_INTERACTIVE = $oldGcm
        $env:GIT_SSH_COMMAND = $oldSsh
    }
}

function Set-RepoStatusField {
    <#
    .SYNOPSIS
        Sets a field on a repo status object safely.

    .DESCRIPTION
        Repo status objects are expected to be hashtables, but in some environments
        or call paths they may become PSCustomObjects. This helper ensures fields
        can be added/updated without throwing PropertyAssignmentException.

    .PARAMETER Status
        The repo status object (hashtable or PSCustomObject).

    .PARAMETER Name
        The field name to set.

    .PARAMETER Value
        The value to assign.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [object]$Status,

        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter()]
        [object]$Value
    )

    if ($Status -is [System.Collections.IDictionary]) {
        $Status[$Name] = $Value
        return
    }

    if ($null -eq $Status) {
        return
    }

    $Status | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-RepoStatus {
    <#
    .SYNOPSIS
        Gets the detailed status of a git repository across all local branches
    .PARAMETER RepoPath
        Path to the git repository
    .RETURNS
        Hashtable with status information
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath
    )
    
    $result = @{
        path = $RepoPath
        name = Split-Path $RepoPath -Leaf
        isGitRepo = $false
        currentBranch = ""
        hasUncommittedChanges = $false
        hasUntrackedFiles = $false
        hasRemote = $false
        branches = @() # Array of branch status objects
        status = "unknown"
        message = ""
        canPull = $false
        pullResult = $null
        originalBranch = ""  # Store user's original branch for auto-pull
    }
    
    Push-Location $RepoPath
    try {
        # Check if it's a git repo
        $gitDir = Run-GitCommand -Arguments "rev-parse", "--git-dir" -WorkingDirectory $RepoPath
        if ($LASTEXITCODE -ne 0) {
            $result.status = "not_git"
            $result.message = "Not a git repository"
            return $result
        }
        
        $result.isGitRepo = $true
        
        # Get current branch
        $branchInfo = Run-GitCommand -Arguments "rev-parse", "--abbrev-ref", "HEAD" -WorkingDirectory $RepoPath
        $result.currentBranch = ($branchInfo | Select-Object -First 1).Trim()
        $result.originalBranch = $result.currentBranch  # Store for auto-pull restoration
        
        # Check for uncommitted changes
        $statusLines = Run-GitCommand -Arguments "status", "--porcelain" -WorkingDirectory $RepoPath
        $hasOnlySubmoduleChanges = $false
        if ($statusLines) {
            $staged = $statusLines | Where-Object { $_ -match "^[MADRC]" }
            $unstaged = $statusLines | Where-Object { $_ -match "^.[MADRC]" }
            $untracked = $statusLines | Where-Object { $_ -match "^\?\?" }
            $submoduleChanges = $statusLines | Where-Object { $_ -match "^M " }
            
            # Check if all changes are submodule changes
            $nonSubmoduleChanges = $statusLines | Where-Object { $_ -notmatch "^M " -and $_ -notmatch "^\?\?" }
            if ($nonSubmoduleChanges) {
                $result.hasUncommittedChanges = $true
            } elseif ($submoduleChanges) {
                $hasOnlySubmoduleChanges = $true
            }
            if ($untracked) {
                $result.hasUntrackedFiles = $true
            }
        }
        
        # Check for remote
        $remotes = Run-GitCommand -Arguments "remote" -WorkingDirectory $RepoPath
        $result.hasRemote = [bool]$remotes
        
        if ($result.hasRemote) {
            # Only fetch/compute branch tracking status when the working tree is clean.
            # If a repo is dirty, we won't pull anyway, and fetching may trigger auth prompts.
            if (-not ($result.hasUncommittedChanges -or $result.hasUntrackedFiles)) {
                # Fetch to check for updates (quiet, non-interactive)
                $fetchLines = Run-GitCommand -Arguments "fetch", "--all", "--quiet" -WorkingDirectory $RepoPath
                if ($LASTEXITCODE -ne 0) {
                    $fetchMessage = ($fetchLines | Select-Object -First 1)
                    if (-not $fetchMessage) {
                        $fetchMessage = "Git fetch failed"
                    }
                    $result.status = "error"
                    if ($fetchMessage -match "(?i)(user cancelled dialog|authentication failed|could not read username|terminal prompts disabled|credential|authorization)") {
                        $result.message = "Authentication required. Run: cd `"$RepoPath`" && git fetch"
                    } else {
                        $result.message = "Fetch failed: $fetchMessage"
                    }
                    return $result
                }
                
                # Get all local branches and their status relative to upstream
                $branchList = Run-GitCommand -Arguments "branch", "--format=%(refname:short)|%(upstream:short)" -WorkingDirectory $RepoPath
                foreach ($line in $branchList) {
                    if ($line -match "^(.+)\|(.+)$") {
                        $branchName = $matches[1]
                        $upstream = $matches[2]
                        
                        if ($upstream) {
                            $aheadStr = (Run-GitCommand -Arguments "rev-list", "--count", "$upstream..$branchName" -WorkingDirectory $RepoPath | Select-Object -First 1).ToString().Trim()
                            $behindStr = (Run-GitCommand -Arguments "rev-list", "--count", "$branchName..$upstream" -WorkingDirectory $RepoPath | Select-Object -First 1).ToString().Trim()
                            
                            $ahead = 0
                            $behind = 0
                            if ($aheadStr -match "^\d+$") { $ahead = [int]$aheadStr }
                            if ($behindStr -match "^\d+$") { $behind = [int]$behindStr }
                            
                            $branchStatus = @{
                                name = $branchName
                                upstream = $upstream
                                ahead = $ahead
                                behind = $behind
                            }
                            $result.branches += $branchStatus
                        }
                    }
                }
            }
        }
        
        # Check for submodule updates (even if only submodule changes exist)
        if (-not $anyDiverged) {
            $submoduleCheck = Test-SubmoduleUpdates -RepoPath $RepoPath
            if ($submoduleCheck.hasUpdates) {
                $result.status = "submodule_updates"
                $result.message = "Submodules have updates available"
                $result.canPull = $true
                return $result
            }
        }
        
        # Determine overall status
        if (-not $result.hasRemote) {
            $result.status = "no_remote"
            $result.message = "No remote configured"
        } elseif ($result.hasUncommittedChanges -or $result.hasUntrackedFiles) {
            $result.status = "dirty"
            if ($result.hasUncommittedChanges) {
                $result.message = "Has uncommitted changes"
            } else {
                $result.message = "Has untracked files"
            }
        } elseif ($hasOnlySubmoduleChanges) {
            # Repository is only dirty due to submodule changes - treat as submodule updates
            $submoduleCheck = Test-SubmoduleUpdates -RepoPath $RepoPath
            if ($submoduleCheck.hasUpdates) {
                $result.status = "submodule_updates"
                $result.message = "Submodules have updates available"
                $result.canPull = $true
                return $result
            } else {
                # Submodule changes but no updates available
                $result.status = "dirty"
                $result.message = "Has submodule changes"
            }
        } else {
            # Evaluate all branches
            $anyBehind = $result.branches | Where-Object { $_.behind -gt 0 }
            $anyAhead = $result.branches | Where-Object { $_.ahead -gt 0 }
            $anyDiverged = $result.branches | Where-Object { $_.ahead -gt 0 -and $_.behind -gt 0 }
            
            if ($anyDiverged) {
                $result.status = "diverged"
                $result.message = "Some branches have diverged"
            } elseif ($anyBehind) {
                $result.status = "behind"
                $result.message = "$($anyBehind.Count) branch(es) behind"
                $result.canPull = $true
            } elseif ($anyAhead) {
                $result.status = "ahead"
                $result.message = "$($anyAhead.Count) branch(es) ahead"
            } else {
                $result.status = "up_to_date"
                $result.message = "All branches up to date"
            }
        }
        
    } catch {
        $result.status = "error"
        $result.message = "Error: $_"
    } finally {
        Pop-Location
    }
    
    return $result
}

function Invoke-SafePull {
    <#
    .SYNOPSIS
        Performs a safe git pull on all branches that are behind
    .PARAMETER RepoPath
        Path to the git repository
    .RETURNS
        Hashtable with pull results summary
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath
    )
    
    $results = Invoke-PullAllBranches -RepoPath $RepoPath
    
    $successCount = ($results | Where-Object { $_.success }).Count
    $totalCount = $results.Count
    $pulledCount = ($results | Where-Object { $_.success -and $_.message -match "Pulled" }).Count
    
    return @{
        success = ($successCount -eq $totalCount)
        message = "Updated $pulledCount branch(es)"
        detailResults = $results
    }
}

function Invoke-PullAllBranches {
    <#
    .SYNOPSIS
        Pulls all branches of a repository (if safe)
    .PARAMETER RepoPath
        Path to the git repository
    .RETURNS
        Array of branch pull results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath
    )
    
    $results = @()
    
    Push-Location $RepoPath
    try {
        $originalBranch = (Run-GitCommand -Arguments "rev-parse", "--abbrev-ref", "HEAD" -WorkingDirectory $RepoPath | Select-Object -First 1).ToString().Trim()
        $branchInfo = Run-GitCommand -Arguments "branch", "--format=%(refname:short)|%(upstream:short)" -WorkingDirectory $RepoPath
        
        foreach ($line in $branchInfo) {
            if ($line -match "^(.+)\|(.+)$") {
                $branch = $matches[1]
                $upstream = $matches[2]
                
                $branchResult = @{
                    branch = $branch
                    success = $false
                    message = ""
                    skipped = $false
                }
                
                if (-not $upstream) {
                    $branchResult.skipped = $true
                    $branchResult.message = "No upstream tracking"
                    $results += $branchResult
                    continue
                }
                
                # Check behind count
                $behindStr = (Run-GitCommand -Arguments "rev-list", "--count", "$branch..$upstream" -WorkingDirectory $RepoPath | Select-Object -First 1).ToString().Trim()
                $behind = 0
                if ($behindStr -match "^\d+$") {
                    $behind = [int]$behindStr
                }
                if ($behind -eq 0) {
                    $branchResult.success = $true
                    $branchResult.message = "Already up to date"
                    $results += $branchResult
                    continue
                }
                
                # Switch to branch if necessary
                if ($branch -ne $originalBranch) {
                    Run-GitCommand -Arguments "checkout", "$branch", "--quiet" -WorkingDirectory $RepoPath
                    if ($LASTEXITCODE -ne 0) {
                        $branchResult.message = "Could not checkout"
                        $results += $branchResult
                        continue
                    }
                }
                
                # Check if clean (needed before pull)
                $status = Run-GitCommand -Arguments "status", "--porcelain" -WorkingDirectory $RepoPath
                if ($status) {
                    $branchResult.message = "Has local changes"
                    if ($branch -ne $originalBranch) {
                         Run-GitCommand -Arguments "checkout", "$originalBranch", "--quiet" -WorkingDirectory $RepoPath
                    }
                    $results += $branchResult
                    continue
                }
                
                # Try pull
                Run-GitCommand -Arguments "pull", "--ff-only" -WorkingDirectory $RepoPath
                if ($LASTEXITCODE -eq 0) {
                    $branchResult.success = $true
                    $branchResult.message = "Pulled $behind new commit(s)"
                } else {
                    $branchResult.message = "Pull failed"
                }
                
                $results += $branchResult
            }
        }
        
        # Return to original branch if we moved
        $currentBranch = (Run-GitCommand -Arguments "rev-parse", "--abbrev-ref", "HEAD" -WorkingDirectory $RepoPath | Select-Object -First 1).ToString().Trim()
        if ($currentBranch -ne $originalBranch) {
            Run-GitCommand -Arguments "checkout", "$originalBranch", "--quiet" -WorkingDirectory $RepoPath
        }
        
    } catch {
        Write-Host "Error pulling branches: $_" -ForegroundColor Red
    } finally {
        Pop-Location
    }
    
    return $results
}

function Invoke-RepoScan {
    <#
    .SYNOPSIS
        Scans all configured folders for git repos and checks their status
    .PARAMETER DryRun
        If true, don't pull - just show status
    .PARAMETER TestLimit
        If specified, limit to first N repositories (for test mode)
    .RETURNS
        Array of repo status results
    #>
    param(
        [switch]$DryRun,
        [int]$TestLimit = 0
    )
    
    $config = Get-WatchedFolders
    $allResults = @()
    
    foreach ($folder in $config.folders) {
        if (-not (Test-Path $folder)) {
            Write-Host "[!] Folder not found: $folder" -ForegroundColor Yellow
            continue
        }
        
        Write-Host "[>] Scanning: $folder" -ForegroundColor Cyan
        
        # Get first-level subdirectories
        $subDirs = Get-ChildItem -Path $folder -Directory -ErrorAction SilentlyContinue
        
        foreach ($subDir in $subDirs) {
            $repoPath = $subDir.FullName
            
            # Check if it's a git repo
            if (-not (Test-Path (Join-Path $repoPath ".git"))) {
                continue
            }
            
            Write-Host "   [?] Checking: $($subDir.Name)..." -ForegroundColor Gray -NoNewline
            
            $status = Get-RepoStatus -RepoPath $repoPath
            
            # Show immediate status indicator
            switch ($status.status) {
                "up_to_date" { Write-Host " [OK]" -ForegroundColor Green }
                "behind" { Write-Host " [v]" -ForegroundColor Yellow }
                "ahead" { Write-Host " [^]" -ForegroundColor Blue }
                "diverged" { Write-Host " [!]" -ForegroundColor Red }
                "dirty" { Write-Host " [~]" -ForegroundColor Magenta }
                "no_remote" { Write-Host " [-]" -ForegroundColor Gray }
                "error" { Write-Host " [X]" -ForegroundColor Red }
                default { Write-Host " [?]" -ForegroundColor Gray }
            }
            
            # Try to pull if safe and not dry run
            if (-not $DryRun -and $status.canPull) {
                Write-Host "      [v] Pulling..." -ForegroundColor Yellow -NoNewline
                try {
                    # Handle submodule updates specially
                    if ($status.status -eq "submodule_updates") {
                        $submoduleResult = Update-Submodules -RepoPath $repoPath -RepoName $status.name
                        Set-RepoStatusField -Status $status -Name "pullResult" -Value $submoduleResult
                        
                        if ($submoduleResult.success) {
                            Write-Host " $($submoduleResult.message)" -ForegroundColor Green
                            Set-RepoStatusField -Status $status -Name "status" -Value "pulled"
                            Set-RepoStatusField -Status $status -Name "message" -Value $submoduleResult.message
                        } else {
                            Write-Host " Failed" -ForegroundColor Red
                        }
                    } elseif ($status.status -eq "behind") {
                        # Auto-pull behind repos even if on different branch
                        $originalBranch = $status.originalBranch
                        $branchesBehind = $status.branches | Where-Object { $_.behind -gt 0 }
                        $pulledCount = 0
                        $failedCount = 0
                        
                        foreach ($branchInfo in $branchesBehind) {
                            $branchName = $branchInfo.name
                            
                            # Switch to branch if needed
                            if ($branchName -ne $originalBranch) {
                                Run-GitCommand -Arguments "checkout", $branchName, "--quiet" -WorkingDirectory $repoPath
                                if ($LASTEXITCODE -ne 0) {
                                    $failedCount++
                                    continue
                                }
                            }
                            
                            # Check if clean (should be, but double-check)
                            $statusCheck = Run-GitCommand -Arguments "status", "--porcelain" -WorkingDirectory $repoPath
                            if ($statusCheck) {
                                # Not clean, skip this branch
                                if ($branchName -ne $originalBranch) {
                                    Run-GitCommand -Arguments "checkout", $originalBranch, "--quiet" -WorkingDirectory $repoPath
                                }
                                $failedCount++
                                continue
                            }
                            
                            # Get behind count before pull to detect if pull actually updated anything
                            $behindBefore = (Run-GitCommand -Arguments "rev-list", "--count", "$branchName..$($branchInfo.upstream)" -WorkingDirectory $repoPath | Select-Object -First 1).ToString().Trim()
                            if ($behindBefore -match "^\d+$") {
                                $behindBefore = [int]$behindBefore
                            } else {
                                $behindBefore = 0
                            }
                            
                            # Pull the branch
                            Run-GitCommand -Arguments "pull", "--ff-only" -WorkingDirectory $repoPath
                            
                            # Check if pull actually updated the repository by checking behind count again
                            $behindAfter = (Run-GitCommand -Arguments "rev-list", "--count", "$branchName..$($branchInfo.upstream)" -WorkingDirectory $repoPath | Select-Object -First 1).ToString().Trim()
                            if ($behindAfter -match "^\d+$") {
                                $behindAfter = [int]$behindAfter
                            } else {
                                $behindAfter = 0
                            }
                            
                            # Count as successful pull only if exit code was 0 AND repository was actually updated
                            if ($LASTEXITCODE -eq 0 -and $behindAfter -lt $behindBefore) {
                                $pulledCount++
                            } else {
                                $failedCount++
                            }
                            
                            # Return to original branch if we switched
                            if ($branchName -ne $originalBranch) {
                                Run-GitCommand -Arguments "checkout", $originalBranch, "--quiet" -WorkingDirectory $repoPath
                            }
                        }
                        
                        # Update status based on results
                        if ($failedCount -eq 0) {
                            Write-Host " Auto-pulled $pulledCount branch(es)" -ForegroundColor Green
                            Set-RepoStatusField -Status $status -Name "status" -Value "pulled"
                            Set-RepoStatusField -Status $status -Name "message" -Value "Auto-pulled $pulledCount branch(es)"
                        } else {
                            Write-Host " Partial: $pulledCount pulled, $failedCount failed" -ForegroundColor Yellow
                            Set-RepoStatusField -Status $status -Name "message" -Value "Partial: $pulledCount pulled, $failedCount failed"
                        }
                        
                        Set-RepoStatusField -Status $status -Name "pullResult" -Value @{
                            success = ($failedCount -eq 0)
                            message = "Auto-pulled $pulledCount, $failedCount failed"
                        }
                    } else {
                        $pullResult = Invoke-SafePull -RepoPath $repoPath
                        Set-RepoStatusField -Status $status -Name "pullResult" -Value $pullResult
                        
                        if ($pullResult.success) {
                            Write-Host " $($pullResult.message)" -ForegroundColor Green
                            Set-RepoStatusField -Status $status -Name "status" -Value "pulled"
                            Set-RepoStatusField -Status $status -Name "message" -Value $pullResult.message
                        } else {
                            Write-Host " Failed" -ForegroundColor Red
                        }
                    }
                } catch {
                    $errorMessage = $_.Exception.Message
                    Write-Host " Failed" -ForegroundColor Red
                    Set-RepoStatusField -Status $status -Name "pullResult" -Value @{
                        success = $false
                        message = "Pull failed: $errorMessage"
                    }
                }
            }
            
            $allResults += $status
            
            # Check test limit
            if ($TestLimit -gt 0 -and $allResults.Count -ge $TestLimit) {
                Write-Host ""
                Write-Host "[i] Test limit reached: checked $TestLimit repositories" -ForegroundColor Yellow
                break
            }
        }
        
        # Check test limit after each folder
        if ($TestLimit -gt 0 -and $allResults.Count -ge $TestLimit) {
            break
        }
    }
    
    return $allResults
}

function Test-SubmoduleUpdates {
    <#
    .SYNOPSIS
        Checks if a repository has submodules with updates available
    .PARAMETER RepoPath
        Path to the repository
    .RETURNS
        Object with hasSubmodules and hasUpdates properties
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath
    )
    
    $result = @{
        hasSubmodules = $false
        hasUpdates = $false
        submodulesToUpdate = @()
    }
    
    try {
        # Check if repository has submodules
        $submoduleStatus = Run-GitCommand -Arguments "submodule", "status" -WorkingDirectory $RepoPath -TimeoutSeconds 10
        
        if ($LASTEXITCODE -eq 0 -and $submoduleStatus) {
            $result.hasSubmodules = $true
            
            # Parse submodule status to find updates
            foreach ($line in $submoduleStatus -split "`n") {
                if ($line -match '^[+-]') {
                    $result.hasUpdates = $true
                    # Extract submodule name (second field)
                    $parts = $line -split '\s+'
                    if ($parts.Length -ge 2) {
                        $result.submodulesToUpdate += $parts[1]
                    }
                }
            }
        }
    } catch {
        # Ignore errors - assume no submodules
    }
    
    return $result
}

function Update-Submodules {
    <#
    .SYNOPSIS
        Updates submodules in a repository safely
    .PARAMETER RepoPath
        Path to the repository
    .PARAMETER RepoName
        Name of the repository for display
    .RETURNS
        Object with success and message properties
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$RepoName
    )
    
    Write-Host ""
    Write-Host "[submodules] Updating submodules in $RepoName..." -ForegroundColor Cyan
    
    try {
        # Get submodules that need updates
        $submoduleStatus = Run-GitCommand -Arguments "submodule", "status" -WorkingDirectory $RepoPath -TimeoutSeconds 10
        $submodulesToUpdate = @()
        
        foreach ($line in $submoduleStatus -split "`n") {
            if ($line -match '^[+-]') {
                $parts = $line -split '\s+'
                if ($parts.Length -ge 2) {
                    $submodulesToUpdate += $parts[1]
                }
            }
        }
        
        if ($submodulesToUpdate.Count -eq 0) {
            Write-Host "   [i] No submodule updates needed" -ForegroundColor Gray
            return @{ success = $true; message = "No submodule updates needed" }
        }
        
        $updatedCount = 0
        $failedCount = 0
        
        foreach ($submodule in $submodulesToUpdate) {
            Write-Host "   [>] Updating $submodule..." -ForegroundColor Yellow -NoNewline
            try {
                $null = Run-GitCommand -Arguments "submodule", "update", "--remote", $submodule -WorkingDirectory $RepoPath -TimeoutSeconds 30
                if ($LASTEXITCODE -eq 0) {
                    Write-Host " OK" -ForegroundColor Green
                    $updatedCount++
                } else {
                    Write-Host " FAILED" -ForegroundColor Red
                    $failedCount++
                }
            } catch {
                Write-Host " FAILED" -ForegroundColor Red
                $failedCount++
            }
        }
        
        # Commit submodule updates if any were successful
        if ($updatedCount -gt 0) {
            Write-Host "   [>] Committing submodule updates..." -ForegroundColor Yellow -NoNewline
            try {
                # Stage changes first
                $null = Run-GitCommand -Arguments "add", "." -WorkingDirectory $RepoPath -TimeoutSeconds 10
                # Check if there are changes to commit
                $stagedChanges = Run-GitCommand -Arguments "diff", "--cached", "--quiet" -WorkingDirectory $RepoPath -TimeoutSeconds 10
                if ($LASTEXITCODE -eq 0) {
                    # No staged changes, but submodules were updated
                    Write-Host " [i] Submodules updated but no commit needed" -ForegroundColor Cyan
                } else {
                    # There are changes to commit
                    $null = Run-GitCommand -Arguments "commit", "-m", "Auto-update submodules ($updatedCount updated)" -WorkingDirectory $RepoPath -TimeoutSeconds 10
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " OK" -ForegroundColor Green
                    } else {
                        Write-Host " FAILED" -ForegroundColor Red
                        return @{ success = $false; message = "Failed to commit submodule updates" }
                    }
                }
                Write-Host ""
                Write-Host "[!] IMPORTANT: Submodules were automatically updated!" -ForegroundColor Yellow
                Write-Host "   Please test $RepoName to ensure it still works as expected" -ForegroundColor Yellow
                Write-Host "   Review the submodule changes: git log --oneline -5" -ForegroundColor Yellow
                return @{ success = $true; message = "Updated $updatedCount submodule(s)" }
            } catch {
                Write-Host " FAILED" -ForegroundColor Red
                return @{ success = $false; message = "Failed to commit submodule updates" }
            }
        }
        
        return @{ success = $true; message = "No submodule updates were needed" }
        
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Host ("   Error updating submodules: " + $errorMessage) -ForegroundColor Red
        return @{ success = $false; message = ('Error updating submodules: ' + $errorMessage) }
    }
}
