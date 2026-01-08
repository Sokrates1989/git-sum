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
        $error = $process.StandardError.ReadToEnd()
        
        $lines = @()
        if ($output) { 
            $splitLines = $output -split "`r?`n" | Where-Object { $_ } | ForEach-Object { $_.ToString() }
            if ($splitLines) { $lines += $splitLines }
        }
        if ($error) { 
            $splitError = $error -split "`r?`n" | Where-Object { $_ } | ForEach-Object { $_.ToString() }
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
    }
    
    Push-Location $RepoPath
    try {
        # Check if it's a git repo
        $gitDir = Run-GitCommand -Arguments "rev-parse", "--git-dir" -WorkingDirectory $RepoPath
        if ($LASTEXITCODE -ne 0) {
            $result.status = "not_git"
            $result.message = "Not a git repository"
            Pop-Location
            return $result
        }
        
        $result.isGitRepo = $true
        
        # Get current branch
        $branchInfo = Run-GitCommand -Arguments "rev-parse", "--abbrev-ref", "HEAD" -WorkingDirectory $RepoPath
        $result.currentBranch = ($branchInfo | Select-Object -First 1).Trim()
        
        # Check for uncommitted changes
        $statusLines = Run-GitCommand -Arguments "status", "--porcelain" -WorkingDirectory $RepoPath
        if ($statusLines) {
            $staged = $statusLines | Where-Object { $_ -match "^[MADRC]" }
            $unstaged = $statusLines | Where-Object { $_ -match "^.[MADRC]" }
            $untracked = $statusLines | Where-Object { $_ -match "^\?\?" }
            
            if ($staged -or $unstaged) {
                $result.hasUncommittedChanges = $true
            }
            if ($untracked) {
                $result.hasUntrackedFiles = $true
            }
        }
        
        # Check for remote
        $remotes = Run-GitCommand -Arguments "remote" -WorkingDirectory $RepoPath
        $result.hasRemote = [bool]$remotes
        
        if ($result.hasRemote) {
            # Fetch to check for updates (quiet, non-interactive)
            Run-GitCommand -Arguments "fetch", "--all", "--quiet" -WorkingDirectory $RepoPath
            
            # Get all local branches and their status relative to upstream
            $branchList = Run-GitCommand -Arguments "branch", "--format=%(refname:short)|%(upstream:short)" -WorkingDirectory $RepoPath
            foreach ($line in $branchList) {
                if ($line -match "^(.+)\|(.+)$") {
                    $branchName = $matches[1]
                    $upstream = $matches[2]
                    
                    if ($upstream) {
                        $aheadStr = (Run-GitCommand -Arguments "rev-list", "--count", "$upstream..$branchName" -WorkingDirectory $RepoPath)[0].ToString()
                        $behindStr = (Run-GitCommand -Arguments "rev-list", "--count", "$branchName..$upstream" -WorkingDirectory $RepoPath)[0].ToString()
                        
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
        
        # Determine overall status
        if (-not $result.hasRemote) {
            $result.status = "no_remote"
            $result.message = "No remote configured"
        } elseif ($result.hasUncommittedChanges) {
            $result.status = "dirty"
            $result.message = "Has uncommitted changes"
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
        $originalBranch = (Run-GitCommand -Arguments "rev-parse", "--abbrev-ref", "HEAD" -WorkingDirectory $RepoPath)[0].ToString()
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
                $behind = [int](Run-GitCommand -Arguments "rev-list", "--count", "$branch..$upstream" -WorkingDirectory $RepoPath)[0].ToString()
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
        $currentBranch = (Run-GitCommand -Arguments "rev-parse", "--abbrev-ref", "HEAD" -WorkingDirectory $RepoPath)[0].ToString()
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
    .RETURNS
        Array of repo status results
    #>
    param(
        [switch]$DryRun
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
                default { Write-Host " [?]" -ForegroundColor Gray }
            }
            
            # Try to pull if safe and not dry run
            if (-not $DryRun -and $status.canPull) {
                Write-Host "      [v] Pulling..." -ForegroundColor Yellow -NoNewline
                $pullResult = Invoke-SafePull -RepoPath $repoPath
                $status.pullResult = $pullResult
                
                if ($pullResult.success) {
                    Write-Host " $($pullResult.message)" -ForegroundColor Green
                    $status.status = "pulled"
                    $status.message = $pullResult.message
                } else {
                    Write-Host " Failed" -ForegroundColor Red
                }
            }
            
            $allResults += $status
        }
    }
    
    return $allResults
}
