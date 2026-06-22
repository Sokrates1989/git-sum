<#
.SYNOPSIS
    UI helper functions for git-sum
    
.DESCRIPTION
    Provides functions for displaying formatted output, summaries, and interactive elements.
#>

function Show-Summary {
    <#
    .SYNOPSIS
        Displays a summary of repository scan results
    .PARAMETER Results
        Array of repo status results
    .PARAMETER DryRun
        If true, indicates this was a dry run
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Results,
        [switch]$DryRun
    )
    
    if ($Results.Count -eq 0) {
        Write-Host ""
        Write-Host "[!] No repositories found in watched folders." -ForegroundColor Yellow
        Write-Host "   Run 'git-sum -a' to add folders containing git repos." -ForegroundColor Gray
        return
    }
    
    # Group by status
    $upToDate = @($Results | Where-Object { $_.status -eq "up_to_date" })
    $pulled = @($Results | Where-Object { $_.status -eq "pulled" })
    $autoPushed = @($Results | Where-Object { $_.status -eq "auto_pushed" })
    $behind = @($Results | Where-Object { $_.status -eq "behind" })
    $ahead = @($Results | Where-Object { $_.status -eq "ahead" })
    $diverged = @($Results | Where-Object { $_.status -eq "diverged" })
    $dirty = @($Results | Where-Object { $_.status -eq "dirty" })
    $noRemote = @($Results | Where-Object { $_.status -eq "no_remote" })
    $submoduleUpdates = @($Results | Where-Object { $_.status -eq "submodule_updates" })
    $errors = @($Results | Where-Object { $_.status -eq "error" -or $_.status -eq "not_git" })
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "[*] Summary" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Quick stats line
    Write-Host "   Total repositories scanned: $($Results.Count)" -ForegroundColor White
    Write-Host ""
    
    # Status breakdown
    if ($pulled.Count -gt 0) {
        Write-Host "   [OK] Pulled:      $($pulled.Count)" -ForegroundColor Green
    }
    if ($autoPushed.Count -gt 0) {
        Write-Host "   [^] Pushed:       $($autoPushed.Count)" -ForegroundColor Green
    }
    if ($upToDate.Count -gt 0) {
        Write-Host "   [OK] Up to date:  $($upToDate.Count)" -ForegroundColor Green
    }
    if ($behind.Count -gt 0) {
        Write-Host "   [v] Behind:      $($behind.Count)" -ForegroundColor Yellow
    }
    if ($ahead.Count -gt 0) {
        Write-Host "   [^] Ahead:       $($ahead.Count)" -ForegroundColor Blue
    }
    if ($diverged.Count -gt 0) {
        Write-Host "   [!] Diverged:    $($diverged.Count)" -ForegroundColor Red
    }
    if ($dirty.Count -gt 0) {
        Write-Host "   [~] Dirty:       $($dirty.Count)" -ForegroundColor Magenta
    }
    if ($noRemote.Count -gt 0) {
        Write-Host "   [-] No remote:   $($noRemote.Count)" -ForegroundColor Gray
    }
    if ($submoduleUpdates.Count -gt 0) {
        Write-Host "   [S] Submodules:   $($submoduleUpdates.Count)" -ForegroundColor Cyan
    }
    if ($errors.Count -gt 0) {
        Write-Host "   [X] Errors:      $($errors.Count)" -ForegroundColor Red
    }
    
    # Show successfully updated/pushed repos (so user sees what changed)
    if ($pulled.Count -gt 0 -or $autoPushed.Count -gt 0) {
        Write-Host ""
        Write-Host "---------------------------------------------------------------" -ForegroundColor Green
        Write-Host "[OK] Successfully Updated Repositories" -ForegroundColor Green
        Write-Host "---------------------------------------------------------------" -ForegroundColor Green
        Write-Host ""
        
        foreach ($repo in $pulled) {
            Write-Host "   [OK] $($repo.name)" -ForegroundColor Green
            Write-Host "      Path:    $($repo.path)" -ForegroundColor DarkGray
            Write-Host "      Updated: $($repo.message)" -ForegroundColor Gray
            Write-Host ""
        }

        foreach ($repo in $autoPushed) {
            Write-Host "   [^] $($repo.name)" -ForegroundColor Green
            Write-Host "      Path:    $($repo.path)" -ForegroundColor DarkGray
            Write-Host "      Pushed:  $($repo.message)" -ForegroundColor Gray
            if ($repo.hasUncommittedChanges -or $repo.hasUntrackedFiles) {
                Write-Host "      [~] Note: repo still has local uncommitted changes" -ForegroundColor Yellow
            }
            # Show branches that were NOT pushed (behind/diverged) so user is aware
            if ($repo.branches) {
                $skipped = $repo.branches | Where-Object { $_.behind -gt 0 }
                if ($skipped) {
                    Write-Host "      [!] Branches still needing attention:" -ForegroundColor Yellow
                    foreach ($branch in $skipped) {
                        if ($branch.ahead -gt 0) {
                            Write-Host "         $($branch.name): Diverged ($($branch.ahead) ahead, $($branch.behind) behind)" -ForegroundColor Red
                        } else {
                            Write-Host "         $($branch.name): $($branch.behind) commits behind" -ForegroundColor Yellow
                        }
                    }
                }
            }
            Write-Host ""
        }
    }
    
    # Show repos that need attention
    $needsAttention = @()
    $needsAttention += $behind
    $needsAttention += $ahead  # Repos still ahead after failed push
    $needsAttention += $diverged
    $needsAttention += $dirty
    $needsAttention += $noRemote
    $needsAttention += $submoduleUpdates
    $needsAttention += $errors
    
    if ($needsAttention.Count -gt 0) {
        Write-Host ""
        Write-Host "---------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "[!] Repositories Needing Attention" -ForegroundColor Yellow
        Write-Host "---------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host ""
        
        foreach ($repo in $needsAttention) {
            Show-RepoAttention -Repo $repo -DryRun:$DryRun
        }
        
        if ($needsAttention.Count -gt 1) {
            Write-Host ""
            Write-Host "===============================================================" -ForegroundColor Cyan
            Write-Host "[*] Summary (Repeated)" -ForegroundColor Cyan
            Write-Host "===============================================================" -ForegroundColor Cyan
            Write-Host ""
            
            Write-Host "   Total repositories scanned: $($Results.Count)" -ForegroundColor White
            Write-Host ""
            
            if ($pulled.Count -gt 0) {
                Write-Host "   [OK] Pulled:      $($pulled.Count)" -ForegroundColor Green
            }
            if ($autoPushed.Count -gt 0) {
                Write-Host "   [^] Pushed:       $($autoPushed.Count)" -ForegroundColor Green
            }
            if ($upToDate.Count -gt 0) {
                Write-Host "   [OK] Up to date:  $($upToDate.Count)" -ForegroundColor Green
            }
            if ($behind.Count -gt 0) {
                Write-Host "   [v] Behind:      $($behind.Count)" -ForegroundColor Yellow
            }
            if ($ahead.Count -gt 0) {
                Write-Host "   [^] Ahead:       $($ahead.Count)" -ForegroundColor Blue
            }
            if ($diverged.Count -gt 0) {
                Write-Host "   [!] Diverged:    $($diverged.Count)" -ForegroundColor Red
            }
            if ($dirty.Count -gt 0) {
                Write-Host "   [~] Dirty:       $($dirty.Count)" -ForegroundColor Magenta
            }
            if ($noRemote.Count -gt 0) {
                Write-Host "   [-] No remote:   $($noRemote.Count)" -ForegroundColor Gray
            }
            if ($submoduleUpdates.Count -gt 0) {
                Write-Host "   [S] Submodules:   $($submoduleUpdates.Count)" -ForegroundColor Cyan
            }
            if ($errors.Count -gt 0) {
                Write-Host "   [X] Errors:      $($errors.Count)" -ForegroundColor Red
            }
        }
    }
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "   (Dry run - no changes were made)" -ForegroundColor Yellow
        Write-Host "   Run 'git-sum' without -s to pull updates" -ForegroundColor Gray
    }
    
    Write-Host ""
}

function Show-RepoAttention {
    <#
    .SYNOPSIS
        Shows details and suggestions for a repo that needs attention
    .PARAMETER Repo
        The repo status hashtable
    .PARAMETER DryRun
        If true, indicates this was a dry run
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Repo,
        [switch]$DryRun
    )
    
    $hasBranchIssues = $false
    
    $icon = switch ($Repo.status) {
        "behind" { "[v]" }
        "ahead" { "[^]" }
        "diverged" { "[!]" }
        "dirty" { "[~]" }
        "no_remote" { "[-]" }
        "submodule_updates" { "[S]" }
        "error" { "[X]" }
        "not_git" { "[?]" }
        default { "*" }
    }
    
    Write-Host "   $icon $($Repo.name)" -ForegroundColor White
    Write-Host "      Path:   $($Repo.path)" -ForegroundColor DarkGray
    
    if ($Repo.status -eq "dirty") {
        Write-Host "      Status: $($Repo.message) (on branch: $($Repo.currentBranch))" -ForegroundColor Gray
        # Show per-branch tracking info so user is aware of branches needing attention
        if ($Repo.branches) {
            foreach ($branch in $Repo.branches) {
                if ($branch.ahead -gt 0 -and $branch.behind -gt 0) {
                    Write-Host "      Branch $($branch.name): Diverged ($($branch.ahead) ahead, $($branch.behind) behind)" -ForegroundColor Red
                    $hasBranchIssues = $true
                } elseif ($branch.ahead -gt 0) {
                    Write-Host "      Branch $($branch.name): $($branch.ahead) commits ahead" -ForegroundColor Blue
                    $hasBranchIssues = $true
                } elseif ($branch.behind -gt 0) {
                    Write-Host "      Branch $($branch.name): $($branch.behind) commits behind" -ForegroundColor Yellow
                    $hasBranchIssues = $true
                }
            }
        }
    } elseif ($Repo.status -eq "no_remote") {
        Write-Host "      Status: $($Repo.message)" -ForegroundColor Gray
    } elseif ($Repo.status -eq "submodule_updates") {
        Write-Host "      Status: $($Repo.message)" -ForegroundColor Gray
        Write-Host "      Will auto-update submodules when pulling" -ForegroundColor DarkGray
    } elseif ($Repo.status -eq "error") {
        Write-Host "      Error:  $($Repo.message)" -ForegroundColor Red
    } else {
        # Show status for all branches that need attention
        $hasBranchIssues = $false
        foreach ($branch in $Repo.branches) {
            if ($branch.ahead -gt 0 -and $branch.behind -gt 0) {
                Write-Host "      Branch $($branch.name): Diverged ($($branch.ahead) ahead, $($branch.behind) behind)" -ForegroundColor Red
                $hasBranchIssues = $true
            } elseif ($branch.ahead -gt 0) {
                Write-Host "      Branch $($branch.name): $($branch.ahead) commits ahead" -ForegroundColor Blue
                $hasBranchIssues = $true
            } elseif ($branch.behind -gt 0) {
                Write-Host "      Branch $($branch.name): $($branch.behind) commits behind" -ForegroundColor Yellow
                $hasBranchIssues = $true
            }
        }
        
        # Create branch-specific commands
        if ($hasBranchIssues) {
            Write-Host "      [>] Run individual branches:" -ForegroundColor Cyan
            foreach ($branch in $Repo.branches) {
                if ($branch.ahead -gt 0 -and $branch.behind -gt 0) {
                    Write-Host "         cd `"$($Repo.path)`"" -ForegroundColor DarkGray
                    Write-Host "         git checkout $($branch.name)" -ForegroundColor DarkGray
                    Write-Host "         git status" -ForegroundColor DarkGray
                } elseif ($branch.ahead -gt 0) {
                    Write-Host "         cd `"$($Repo.path)`"" -ForegroundColor DarkGray
                    Write-Host "         git checkout $($branch.name)" -ForegroundColor DarkGray
                    Write-Host "         git push" -ForegroundColor DarkGray
                } elseif ($branch.behind -gt 0) {
                    Write-Host "         cd `"$($Repo.path)`"" -ForegroundColor DarkGray
                    Write-Host "         git checkout $($branch.name)" -ForegroundColor DarkGray
                    Write-Host "         git pull" -ForegroundColor DarkGray
                }
                Write-Host ""
            }
        }
    }
    
    # Suggest fix (only if no branch-specific commands were shown)
    if (-not $hasBranchIssues) {
        $suggestion = Get-FixSuggestion -Repo $Repo
        if ($suggestion) {
            Write-Host "      [>] Check repository status:" -ForegroundColor Cyan
            # Split the suggestion into multiple lines for easier copying
            if ($suggestion -match 'cd\s+"([^"]+)"') {
                $path = $matches[1]
                # Simple split: everything after "cd " and before ";"
                $parts = $suggestion -split ';\s*', 2
                if ($parts.Length -eq 2) {
                    Write-Host "         cd `"$path`"; $($parts[1].Trim())" -ForegroundColor DarkGray
                }
            }
        }
    }
    
    Write-Host ""
}

function Get-FixSuggestion {
    <#
    .SYNOPSIS
        Gets a fix suggestion for a repo issue
    .PARAMETER Repo
        The repo status hashtable
    .RETURNS
        A suggestion string or $null
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Repo
    )
    
    switch ($Repo.status) {
        "behind" {
            return "Run: cd `"$($Repo.path)`"; git pull"
        }
        "ahead" {
            return "Run: cd `"$($Repo.path)`"; git push"
        }
        "diverged" {
            return "Manual merge needed. Run: cd `"$($Repo.path)`"; git status"
        }
        "dirty" {
            return "Check repository status: cd `"$($Repo.path)`"; git status"
        }
        "no_remote" {
            return "Add remote: cd `"$($Repo.path)`"; git remote add origin <url>"
        }
        "error" {
            return "Check repository: cd `"$($Repo.path)`"; git status"
        }
        default {
            return $null
        }
    }
}

function Write-ColoredLine {
    <#
    .SYNOPSIS
        Writes a line with multiple colored segments
    .PARAMETER Segments
        Array of hashtables with Text and Color properties
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Segments
    )
    
    foreach ($segment in $Segments) {
        Write-Host $segment.Text -ForegroundColor $segment.Color -NoNewline
    }
    Write-Host ""
}

function Show-ProgressBar {
    <#
    .SYNOPSIS
        Shows a simple text-based progress indicator
    .PARAMETER Current
        Current item number
    .PARAMETER Total
        Total items
    .PARAMETER Label
        Label to show
    #>
    param(
        [int]$Current,
        [int]$Total,
        [string]$Label = ""
    )
    
    $percent = [math]::Round(($Current / $Total) * 100)
    $filled = [math]::Round(($Current / $Total) * 20)
    $empty = 20 - $filled
    
    $bar = "[" + ("#" * $filled) + ("-" * $empty) + "]"
    
    Write-Host "`r   $bar $percent% $Label" -NoNewline
}
