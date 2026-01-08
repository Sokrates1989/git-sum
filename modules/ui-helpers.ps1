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
    $behind = @($Results | Where-Object { $_.status -eq "behind" })
    $ahead = @($Results | Where-Object { $_.status -eq "ahead" })
    $diverged = @($Results | Where-Object { $_.status -eq "diverged" })
    $dirty = @($Results | Where-Object { $_.status -eq "dirty" })
    $noRemote = @($Results | Where-Object { $_.status -eq "no_remote" })
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
    if ($errors.Count -gt 0) {
        Write-Host "   [X] Errors:      $($errors.Count)" -ForegroundColor Red
    }
    
    # Show repos that need attention
    $needsAttention = @()
    $needsAttention += $behind
    $needsAttention += $ahead
    $needsAttention += $diverged
    $needsAttention += $dirty
    $needsAttention += $noRemote
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
    
    $icon = switch ($Repo.status) {
        "behind" { "[v]" }
        "ahead" { "[^]" }
        "diverged" { "[!]" }
        "dirty" { "[~]" }
        "no_remote" { "[-]" }
        "error" { "[X]" }
        "not_git" { "[?]" }
        default { "*" }
    }
    
    Write-Host "   $icon $($Repo.name)" -ForegroundColor White
    Write-Host "      Path:   $($Repo.path)" -ForegroundColor DarkGray
    
    if ($Repo.status -eq "dirty") {
        Write-Host "      Status: $($Repo.message) (on branch: $($Repo.currentBranch))" -ForegroundColor Gray
    } elseif ($Repo.status -eq "no_remote") {
        Write-Host "      Status: $($Repo.message)" -ForegroundColor Gray
    } elseif ($Repo.status -eq "error") {
        Write-Host "      Error:  $($Repo.message)" -ForegroundColor Red
    } else {
        # Show status for all branches that need attention
        foreach ($branch in $Repo.branches) {
            if ($branch.ahead -gt 0 -and $branch.behind -gt 0) {
                Write-Host "      Branch $($branch.name): Diverged ($($branch.ahead) ahead, $($branch.behind) behind)" -ForegroundColor Red
            } elseif ($branch.ahead -gt 0) {
                Write-Host "      Branch $($branch.name): $($branch.ahead) commits ahead" -ForegroundColor Blue
            } elseif ($branch.behind -gt 0) {
                Write-Host "      Branch $($branch.name): $($branch.behind) commits behind" -ForegroundColor Yellow
            }
        }
    }
    
    # Suggest fix
    $suggestion = Get-FixSuggestion -Repo $Repo
    if ($suggestion) {
        Write-Host "      [>] $suggestion" -ForegroundColor Cyan
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
            return "Run: cd `"$($Repo.path)`" && git pull"
        }
        "ahead" {
            return "Run: cd `"$($Repo.path)`" && git push"
        }
        "diverged" {
            return "Manual merge needed. Run: cd `"$($Repo.path)`" && git status"
        }
        "dirty" {
            if ($Repo.hasUncommittedChanges) {
                return "Commit or stash changes: cd `"$($Repo.path)`" && git stash"
            } else {
                return "Review changes: cd `"$($Repo.path)`" && git status"
            }
        }
        "no_remote" {
            return "Add remote: cd `"$($Repo.path)`" && git remote add origin <url>"
        }
        "error" {
            return "Check repository: cd `"$($Repo.path)`" && git status"
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
