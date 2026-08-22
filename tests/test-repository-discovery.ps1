<#
.SYNOPSIS
    Verifies direct and first-level repository discovery.
.DESCRIPTION
    Uses disposable directory markers and stubbed status checks so discovery is
    exercised without network access or repository mutations.
#>

$ErrorActionPreference = "Stop"
$TestRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $TestRoot "modules\git-operations.ps1")

$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("git-sum-discovery-" + [guid]::NewGuid())
$directRepository = Join-Path $testDirectory "coding-guidelines"
$nestedContainer = Join-Path $testDirectory "nested"
$nestedRepository = Join-Path $nestedContainer "nested-repository"

try {
    New-Item -ItemType Directory -Path (Join-Path $directRepository ".git") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $nestedRepository ".git") -Force | Out-Null

    $script:watchedFolders = @($directRepository)
    function Get-WatchedFolders {
        return @{
            folders = $script:watchedFolders
        }
    }

    function Get-RepoStatus {
        param(
            [Parameter(Mandatory=$true)]
            [string]$RepoPath
        )

        return @{
            name = Split-Path -Leaf $RepoPath
            path = $RepoPath
            status = "up_to_date"
            message = "Test repository"
            canPull = $false
            canPush = $false
        }
    }

    $directResults = @(Invoke-RepoScan -DryRun)
    if ($directResults.Count -ne 1 -or $directResults[0].path -ne $directRepository) {
        throw "Direct repository watch entry was not detected."
    }

    $script:watchedFolders = @($testDirectory, $directRepository, $nestedContainer)
    $results = @(Invoke-RepoScan -DryRun)
    if ($results.Count -ne 2) {
        throw "Expected 2 unique repositories, found $($results.Count)."
    }

    $resultPaths = @($results | ForEach-Object { $_.path })
    if ($nestedRepository -notin $resultPaths) {
        throw "First-level repository inside a watched container was not detected."
    }

    Write-Host "PowerShell repository discovery passed."
} finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
