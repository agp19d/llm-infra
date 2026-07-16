<#
.SYNOPSIS
  Deploys the GPU box by triggering the apply.yml GitHub Actions workflow.
  Auto-detects your current public IP so you never have to type or edit it
  anywhere -- the security group is locked to whatever this script detects.

.PARAMETER Model
  Optional Ollama model tag to deploy (defaults to the repo's variables.tf default).

.PARAMETER KeyPairName
  Optional EC2 key pair name for SSH access (defaults to "disposable-dev").
#>
param(
  [string]$Model,
  [string]$KeyPairName
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) not found. Install it and run 'gh auth login' first."
}

$ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim()
$myIp = "$ip/32"
Write-Host "Detected public IP: $myIp"

$ghArgs = @("workflow", "run", "apply.yml", "-f", "my_ip=$myIp")
if ($KeyPairName) { $ghArgs += @("-f", "key_pair_name=$KeyPairName") }
if ($Model) { $ghArgs += @("-f", "ollama_model=$Model") }

Write-Host "Triggering GitHub Actions apply..."
gh @ghArgs

Write-Host "Deploy triggered. Watch progress with: gh run watch"
