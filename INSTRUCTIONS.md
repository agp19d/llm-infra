# Running Ollama locally against the GPU box

This repo deploys one disposable EC2 GPU box that runs Ollama. There is no
local inference — your computer is just a *client* talking to the model over
the network. There's also no local Terraform: every deploy/destroy runs
through GitHub Actions, authenticated to AWS via OIDC (no stored AWS keys).
The only thing that runs on your own machine is a one-line helper script that
detects your current public IP and kicks off the workflow.

- `bootstrap/` — the S3 state bucket + GitHub OIDC role. Applied **once, by
  hand**, with your own AWS credentials (chicken-and-egg: CI can't create the
  role it needs in order to authenticate).
- `infra/` — the actual VPC/security-group/GPU-instance/dead-man-switch
  stack. Applied **only** via GitHub Actions (`.github/workflows/`), never
  from your own machine.
- `scripts/` — `deploy.*` / `destroy.*`, thin wrappers around
  `gh workflow run`.

## 0. Prerequisites

- Terraform >= 1.10 and AWS CLI configured with credentials — needed only
  for the one-time bootstrap step below, not for day-to-day use.
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated (`gh auth
  login`) — used by `scripts/deploy.*` / `scripts/destroy.*` to trigger
  workflows.
- An existing EC2 key pair in your AWS account (check with `aws ec2
  describe-key-pairs`). This repo assumes one named `disposable-dev`, with
  the private key kept locally as `disposable-dev.pem` (gitignored, never
  committed) — only needed if you want to SSH into the box directly.
- [Ollama](https://ollama.com/download) installed locally (gives you the
  `ollama` CLI — it doesn't need a GPU, it's just acting as a client here).
- Optionally, [OpenCode](https://opencode.ai) installed locally
  (`npm install -g opencode-ai`).

## 1. Bootstrap (one time only)

```bash
cd bootstrap
terraform init
terraform apply
```

This creates the S3 state bucket (`llm-infra-tfstate-agp19d` by default —
change `var.state_bucket_name` if that's taken, and update the `bucket`
value in `infra/versions.tf` to match) and the GitHub Actions OIDC role.

Take the `github_actions_role_arn` output and set it as a repo variable
(Settings → Secrets and variables → Actions → Variables — it's an ARN, not a
secret, so a plain variable is fine):

```bash
gh variable set AWS_ROLE_ARN --body "<github_actions_role_arn output>"
```

From here on, you never need local AWS credentials again unless you're
re-running bootstrap or destroying it.

## 2. Deploy the GPU box

```powershell
# Windows (PowerShell)
scripts/deploy.ps1
```
```bash
# macOS/Linux
scripts/deploy.sh
```

This detects your current public IP and triggers the `apply.yml` workflow —
you never type or paste an IP anywhere. Watch it run with `gh run watch` or
in the Actions tab. The security group locks SSH (22) and the Ollama API
(11434) to that IP only, never `0.0.0.0/0`.

Optional args (positional for `.sh`, named for `.ps1`): a different Ollama
model tag, a different key pair name — see the script header comments.

The model (default: `rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated`,
set via `var.ollama_model` in `infra/variables.tf`) is pulled automatically
on first boot and can take a few minutes for the ~24GB download.

## 3. Get the box's address

```bash
gh run view --workflow=apply.yml --log | grep gpu_public_ip
```

or check the "Show outputs" step of the latest `apply.yml` run in the
Actions tab. Confirm the model has finished pulling:

```bash
curl http://<gpu_public_ip>:11434/v1/models
```

You should see the model listed under `"data"`. If `"data"` is `null` or the
list is empty, the pull isn't finished yet — wait and retry.

## 4. Run `ollama` from your local computer

Point your local `ollama` CLI at the remote server instead of a local daemon
by setting `OLLAMA_HOST`:

**macOS/Linux:**
```bash
export OLLAMA_HOST=http://<gpu_public_ip>:11434
ollama run rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated
```

**Windows (PowerShell):**
```powershell
$env:OLLAMA_HOST = "http://<gpu_public_ip>:11434"
ollama run rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated
```

This works for any `ollama` subcommand (`ollama ps`, `ollama pull`, etc.) —
they'll all operate against the remote box's model store, not your machine's.

## 5. Attach it to OpenCode

Create (or edit) your OpenCode config. Global config lives at
`~/.config/opencode/opencode.json` (macOS/Linux) or
`%USERPROFILE%\.config\opencode\opencode.json` (Windows) — or drop an
`opencode.json` in your project root for a per-project override.

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

Substitute `<gpu_public_ip>` with the value from step 3, and the model name
with whatever `var.ollama_model` you deployed. Then from any project
directory:

```bash
opencode
```

and select the `gpu-box` provider / model when prompted (or set it as
default per OpenCode's own config docs).

## 6. Making infra changes

Edit anything under `infra/` and open a PR. `plan.yml` runs `terraform
fmt`/`validate`/`plan` and comments the diff on the PR (using a placeholder
IP — it never applies). Once merged, run `scripts/deploy.*` again to
actually apply the change to a running box (or to redeploy fresh).

## 7. Troubleshooting

- **Requests time out from your local machine**: your public IP probably
  changed since you last ran `scripts/deploy.*` — just re-run it.
- **Requests time out when curling from *inside* the box itself**: expected.
  The security group only allows your real IP, and a box can't reach its own
  public IP through the same path your laptop uses. Use `127.0.0.1` when
  testing on-box over SSH.
- **`ollama` service crash-looping on the box** (`systemctl status ollama`
  shows `activating (auto-restart)`): check `journalctl -u ollama -n 50` for
  a permissions error creating `blobs/`. If so:
  ```bash
  ssh -i disposable-dev.pem ubuntu@<gpu_public_ip>
  sudo chown -R ollama:ollama /opt/dlami/nvme/ollama
  sudo systemctl restart ollama
  ```
- **Model pull fails with `unexpected EOF`**: transient network blip, just
  re-run `ollama pull <model>` on the box.
- **Chat request hangs/times out and `nvidia-smi` shows GPU memory barely
  moving**: the model doesn't fit in the box's VRAM and is thrashing trying
  to mmap the overflow from disk. The default 24GB model fits comfortably on
  the default `g6e.xlarge` (1x L40S, 48GB VRAM). If you switch to a larger
  `var.ollama_model`, bump `instance_type` up to a multi-GPU `g6e` size
  (e.g. `g6e.12xlarge`, 4x L40S / 192GB) to match, or expect slow
  CPU-offloaded inference.
- **`apply.yml`/`destroy.yml` fails on `configure-aws-credentials` with an
  OIDC/assume-role error**: check the `AWS_ROLE_ARN` repo variable is set
  (`gh variable list`) and matches bootstrap's `github_actions_role_arn`
  output.

## 8. When you're done

Model weights live on the box's ephemeral NVMe instance store and are wiped
on stop/terminate (this is intentional — nothing there is meant to persist).
A dead-man switch auto-stops the box 5 hours after apply in case you forget,
but stopped still bills for EBS. Actually remove everything with:

```powershell
scripts/destroy.ps1
```
```bash
scripts/destroy.sh
```

To also tear down bootstrap (the state bucket and OIDC role — you'd need to
bootstrap again before deploying anything else):

```bash
cd bootstrap
terraform destroy
```
