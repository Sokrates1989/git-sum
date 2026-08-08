<#
.SYNOPSIS
    Verifies that PowerShell submodule no-ops remain up to date.
.DESCRIPTION
    Exercises the pure summary classifier without fetching or changing repos.
#>

$ErrorActionPreference = "Stop"
$TestRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $TestRoot "modules\git-operations.ps1")

$status = @{ status = "submodule_updates"; message = "" }
Set-SubmoduleUpdateClassification `
    -Status $status `
    -Result @{ success = $true; changed = $false; message = "Submodules already in sync" }
if ($status.status -ne "up_to_date") {
    throw "No-op submodule result was incorrectly classified as pulled."
}

Set-SubmoduleUpdateClassification `
    -Status $status `
    -Result @{ success = $true; changed = $true; message = "Updated 1 submodule(s)" }
if ($status.status -ne "pulled") {
    throw "Changed submodule result was not classified as pulled."
}

Write-Host "PowerShell submodule summary classification passed."
