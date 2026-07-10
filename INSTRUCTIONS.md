# Running Ollama locally against the GPU box

This deploys one disposable EC2 GPU box that runs Ollama. There is no local
inference — your computer is just a *client* talking to the model over the
network. This doc covers: deploying the box, running `ollama` locally against
it, and attaching it to OpenCode.

## 0. Prerequisites

- Terraform >= 1.5, AWS CLI configured with credentials.
- An existing EC2 key pair (check with `aws ec2 describe-key-pairs`). This
  repo already has one: `disposable-dev`, with the private key at
  `disposable-dev.pem` in the repo root.
- [Ollama](https://ollama.com/download) installed on your own computer (this
  gives you the `ollama` CLI — it does not need a GPU, it's just acting as a
  client here).
- Optionally, [OpenCode](https://opencode.ai) installed locally
  (`npm install -g opencode-ai`).

## 1. Deploy the GPU box

```bash
curl -s https://checkip.amazonaws.com   # your public IP, for the my_ip var

terraform apply \
  -var "my_ip=<your-ip>/32" \
  -var "key_pair_name=disposable-dev"
```

SSH (22) and the Ollama API (11434) on the box are locked to `my_ip` only —
if your IP changes later, re-apply with the new value or you'll lose access.

## 2. Get the box's address

```bash
terraform output -raw gpu_public_ip
```

The model (default: `huihui_ai/qwen3-coder-next-abliterated:q4_K`, set via
`var.ollama_model`) is pulled automatically on first boot and can take a few
minutes for the ~52GB download. Check readiness with:

```bash
curl http://<gpu_public_ip>:11434/v1/models
```

You should see the model listed under `"data"`. If `"data"` is `null` or the
list is empty, the pull isn't finished yet — wait and retry.

## 3. Run `ollama` from your local computer

Point your local `ollama` CLI at the remote server instead of a local daemon
by setting `OLLAMA_HOST`:

**macOS/Linux:**
```bash
export OLLAMA_HOST=http://<gpu_public_ip>:11434
ollama run huihui_ai/qwen3-coder-next-abliterated:q4_K
```

**Windows (PowerShell):**
```powershell
$env:OLLAMA_HOST = "http://<gpu_public_ip>:11434"
ollama run huihui_ai/qwen3-coder-next-abliterated:q4_K
```

This works for any `ollama` subcommand (`ollama ps`, `ollama pull`, etc.) —
they'll all operate against the remote box's model store, not your machine's.

## 4. Attach it to OpenCode

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
        "huihui_ai/qwen3-coder-next-abliterated:q4_K": {
          "name": "huihui_ai/qwen3-coder-next-abliterated:q4_K"
        }
      }
    }
  }
}
```

Substitute `<gpu_public_ip>` with the value from step 2, and the model name
with whatever `var.ollama_model` you deployed. Then from any project
directory:

```bash
opencode
```

and select the `gpu-box` provider / model when prompted (or set it as
default per OpenCode's own config docs).

## 5. Troubleshooting

- **Requests time out from your local machine**: your public IP probably
  changed since you last ran `terraform apply` — re-run step 1 with the
  current IP.
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
  to mmap the overflow from disk. The default `g6e.12xlarge` (4x L40S,
  192GB VRAM) comfortably fits the default 52GB model. If you switch
  `instance_type` down to a single-GPU `g6e.xlarge` (48GB VRAM), also switch
  `var.ollama_model` down to `huihui_ai/qwen3-coder-abliterated:30b` (19GB)
  or expect slow CPU-offloaded inference.

## 6. When you're done

Model weights live on the box's ephemeral NVMe instance store and are wiped
on stop/terminate (this is intentional — nothing there is meant to persist).
A dead-man switch auto-stops the box 5 hours after `apply` in case you
forget, but stopped still bills for EBS. Actually remove everything with:

```bash
terraform destroy
```
