# Step by step: get the GPU box talking to local OpenCode

Quick path from "nothing running" to chatting with the model inside OpenCode.
See `INSTRUCTIONS.md` for the full reference (troubleshooting, teardown,
making infra changes); this is just the happy path.

## Prerequisites (one time)

- [GitHub CLI](https://cli.github.com/) installed and authenticated:
  ```bash
  gh auth login
  ```
- [OpenCode](https://opencode.ai) installed locally:
  ```bash
  npm install -g opencode-ai
  ```
- Bootstrap already applied and `AWS_ROLE_ARN` repo variable set (this repo's
  bootstrap has already been run — see `INSTRUCTIONS.md` §1 if starting a
  fresh fork/clone with no bootstrap yet).

## 1. Deploy the GPU box

From the repo root:

```powershell
# Windows (PowerShell)
scripts/deploy.ps1
```
```bash
# macOS/Linux
scripts/deploy.sh
```

This auto-detects your current public IP (no typing/pasting it anywhere) and
triggers the `apply.yml` GitHub Actions workflow, which spins up the GPU
instance and pulls the default model
(`rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated`, ~24GB).

Watch it run:

```bash
gh run watch
```

## 2. Get the box's public IP

Once the workflow finishes:

```bash
gh run view --workflow=apply.yml --log | grep gpu_public_ip
```

(Or open the latest `apply.yml` run in the Actions tab → "Show outputs".)

## 3. Confirm the model finished pulling

The instance boots faster than the ~24GB model download completes, so check:

```bash
curl http://<gpu_public_ip>:11434/v1/models
```

If `"data"` is empty/`null`, wait a bit and retry — the box is still
pulling.

## 4. Point OpenCode at the box

Edit (or create) your OpenCode config:

- macOS/Linux: `~/.config/opencode/opencode.json`
- Windows: `%USERPROFILE%\.config\opencode\opencode.json`
- Or drop an `opencode.json` in your project root for a per-project override.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "gpu-box": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "GPU box (Ollama)",
      "options": {
        "baseURL": "http://<gpu_public_ip>:11434/v1"
      },
      "models": {
        "rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated": {
          "name": "rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated"
        }
      }
    }
  }
}
```

Replace `<gpu_public_ip>` with the value from step 2.

## 5. Run OpenCode

```bash
opencode
```

Select the `gpu-box` provider and the model when prompted (or set it as your
default per OpenCode's own config docs). You're now chatting with the model
running on the GPU box — nothing runs locally except the OpenCode client.

## 6. When you're done

Model weights live on ephemeral NVMe and vanish on stop/terminate anyway, but
to stop billing entirely:

```powershell
scripts/destroy.ps1
```
```bash
scripts/destroy.sh
```

## Troubleshooting

- **OpenCode can't connect / requests time out**: your public IP probably
  changed since you ran `scripts/deploy.*` (the security group only allows
  the IP detected at deploy time) — just re-run `scripts/deploy.*`.
- **`"data"` stays empty for a long time**: check the model actually started
  pulling — see `INSTRUCTIONS.md` §7 for the SSH-based checks.
- Anything else: `INSTRUCTIONS.md` §7 has the full troubleshooting list.
