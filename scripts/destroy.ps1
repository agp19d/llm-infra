<#
.SYNOPSIS
  Tears down every infra/ resource (GPU box, VPC, dead-man switch) by
  triggering the destroy.yml GitHub Actions workflow.
#>
$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) not found. Install it and run 'gh auth login' first."
}

Write-Host "Triggering GitHub Actions destroy -- tears down every infra/ resource."
gh workflow run destroy.yml -f confirm=destroy

Write-Host "Destroy triggered. Watch progress with: gh run watch"
