#!/usr/bin/env bash
# Tears down every infra/ resource (GPU box, VPC, dead-man switch) by
# triggering the destroy.yml GitHub Actions workflow.
set -euo pipefail

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) not found. Install it and run 'gh auth login' first." >&2
  exit 1
}

echo "Triggering GitHub Actions destroy -- tears down every infra/ resource."
gh workflow run destroy.yml -f confirm=destroy

echo "Destroy triggered. Watch progress with: gh run watch"
