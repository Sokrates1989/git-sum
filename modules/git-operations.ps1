<#
.SYNOPSIS
    Git operations for git-sum
    
.DESCRIPTION
    Handles git repository scanning, status checking, and safe pulling.
#>

function Get-RepoStatus {
    <#
    .SYNOPSIS
        Gets the detailed status of a git repository
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
        aheadCount = 0
        behindCount = 0
        hasRemote = $false
        branches = @()
        status = "unknown"
        message = ""
        canPull = $false
        pullResult = $null
    }
    
    Push-Location $RepoPath
    try {
        # Check if it's a git repo
        $gitDir = git rev-parse --git-dir 2>$null
        if (-not $gitDir) {
            $result.status = "not_git"
            $result.message = "Not a git repository"
            Pop-Location
            return $result
        }
        
        $result.isGitRepo = $true
        
        # Get current branch
        $result.currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $result.currentBranch) {
            $result.currentBranch = "(detached)"
        }
        
        # Check for uncommitted changes
        $status = git status --porcelain 2>$null
        if ($status) {
            $staged = $status | Where-Object { $_ -match "^[MADRC]" }
            $unstaged = $status | Where-Object { $_ -match "^.[MADRC]" }
            $untracked = $status | Where-Object { $_ -match "^\?\?" }
            
            if ($staged -or $unstaged) {
                $result.hasUncommittedChanges = $true
            }
            if ($untracked) {
                $result.hasUntrackedFiles = $true
            }
        }
        
        # Check for remote
        $remotes = git remote 2>$null
        $result.hasRemote = [bool]$remotes
        
        if ($result.hasRemote) {
            # Fetch to check for updates (quiet)
            git fetch --all --quiet 2>$null
            
            # Check ahead/behind
            $tracking = git rev-parse --abbrev-ref "@{upstream}" 2>$null
            if ($tracking) {
                $ahead = git rev-list --count "@{upstream}..HEAD" 2>$null
                $behind = git rev-list --count "HEAD..@{upstream}" 2>$null
                
                if ($ahead) { $result.aheadCount = [int]$ahead }
                if ($behind) { $result.behindCount = [int]$behind }
            }
        }
        
        # Get all local branches
        $branches = git branch --format="%(refname:short)" 2>$null
        if ($branches) {
            $result.branches = @($branches)
        }
        
        # Determine overall status and if we can pull
        if (-not $result.hasRemote) {
            $result.status = "no_remote"
            $result.message = "No remote configured"
            $result.canPull = $false
        } elseif ($result.hasUncommittedChanges) {
            $result.status = "dirty"
            $result.message = "Has uncommitted changes"
            $result.canPull = $false
        } elseif ($result.aheadCount -gt 0 -and $result.behindCount -gt 0) {
            $result.status = "diverged"
            $result.message = "Diverged ($($result.aheadCount) ahead, $($result.behindCount) behind)"
            $result.canPull = $false
        } elseif ($result.aheadCount -gt 0) {
            $result.status = "ahead"
            $result.message = "$($result.aheadCount) commits ahead (needs push)"
            $result.canPull = $false
        } elseif ($result.behindCount -gt 0) {
            $result.status = "behind"
            $result.message = "$($result.behindCount) commits behind"
            $result.canPull = $true
        } else {
            $result.status = "up_to_date"
            $result.message = "Up to date"
            $result.canPull = $false
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
        Performs a safe git pull on a repository
    .PARAMETER RepoPath
        Path to the git repository
    .RETURNS
        Hashtable with pull result
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath
    )
    
    $result = @{
        success = $false
        message = ""
        commitsBefore = ""
        commitsAfter = ""
    }
    
    Push-Location $RepoPath
    try {
        $result.commitsBefore = git rev-parse HEAD 2>$null
        
        # Try fast-forward only pull
        $output = git pull --ff-only 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $result.success = $true
            $result.commitsAfter = git rev-parse HEAD 2>$null
            
            if ($result.commitsBefore -eq $result.commitsAfter) {
                $result.message = "Already up to date"
            } else {
                $newCommits = git rev-list --count "$($result.commitsBefore)..$($result.commitsAfter)" 2>$null
                $result.message = "Pulled $newCommits new commit(s)"
            }
        } else {
            $result.message = "Pull failed: $output"
        }
    } catch {
        $result.message = "Error: $_"
    } finally {
        Pop-Location
    }
    
    return $result
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
        $originalBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $branches = git branch --format="%(refname:short)" 2>$null
        
        foreach ($branch in $branches) {
            $branchResult = @{
                branch = $branch
                success = $false
                message = ""
                skipped = $false
            }
            
            # Check if branch has upstream
            $upstream = git rev-parse --abbrev-ref "$branch@{upstream}" 2>$null
            if (-not $upstream) {
                $branchResult.skipped = $true
                $branchResult.message = "No upstream tracking"
                $results += $branchResult
                continue
            }
            
            # Switch to branch
            git checkout $branch --quiet 2>$null
            if ($LASTEXITCODE -ne 0) {
                $branchResult.message = "Could not checkout"
                $results += $branchResult
                continue
            }
            
            # Check if clean
            $status = git status --porcelain 2>$null
            if ($status) {
                $branchResult.message = "Has local changes"
                $results += $branchResult
                continue
            }
            
            # Check if can fast-forward
            $behind = git rev-list --count "HEAD..$upstream" 2>$null
            if ([int]$behind -eq 0) {
                $branchResult.success = $true
                $branchResult.message = "Already up to date"
                $results += $branchResult
                continue
            }
            
            # Try pull
            $pullOutput = git pull --ff-only 2>&1
            if ($LASTEXITCODE -eq 0) {
                $branchResult.success = $true
                $branchResult.message = "Pulled $behind commit(s)"
            } else {
                $branchResult.message = "Pull failed"
            }
            
            $results += $branchResult
        }
        
        # Return to original branch
        git checkout $originalBranch --quiet 2>$null
        
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
