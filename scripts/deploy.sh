#!/usr/bin/env bash
# Deploys the GPU box by triggering the apply.yml GitHub Actions workflow.
# Auto-detects your current public IP so you never have to type or edit it
# anywhere -- the security group is locked to whatever this script detects.
#
# Usage: scripts/deploy.sh [ollama_model] [key_pair_name]
set -euo pipefail

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) not found. Install it and run 'gh auth login' first." >&2
  exit 1
}

MODEL="${1:-}"
KEY_PAIR_NAME="${2:-}"

MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
echo "Detected public IP: $MY_IP"

ARGS=(workflow run apply.yml -f "my_ip=$MY_IP")
[ -n "$KEY_PAIR_NAME" ] && ARGS+=(-f "key_pair_name=$KEY_PAIR_NAME")
[ -n "$MODEL" ] && ARGS+=(-f "ollama_model=$MODEL")

echo "Triggering GitHub Actions apply..."
gh "${ARGS[@]}"

echo "Deploy triggered. Watch progress with: gh run watch"
