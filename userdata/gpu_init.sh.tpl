#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# --- Use the DLAMI's ephemeral NVMe mount for model weights -----------------
# Model weights live on instance store, not the EBS root disk: it's free,
# fast, and vanishes on stop/terminate, which is exactly what we want for a
# disposable box (weights just get re-pulled next boot). The base DLAMI
# already formats and mounts the NVMe instance store at /opt/dlami/nvme via
# its own systemd unit before this script runs, so reuse that mount instead
# of reformatting the same device (which fails with "in use by the system").
if mountpoint -q /opt/dlami/nvme; then
  MODELS_DIR=/opt/dlami/nvme/ollama
else
  NVME_LINK=$(ls /dev/disk/by-id/ | grep -m1 'Amazon_EC2_NVMe_Instance_Storage')
  NVME_DEV=$(readlink -f "/dev/disk/by-id/$NVME_LINK")
  mkfs.ext4 -F "$NVME_DEV"
  mkdir -p /mnt/nvme
  mount "$NVME_DEV" /mnt/nvme
  UUID=$(blkid -s UUID -o value "$NVME_DEV")
  echo "UUID=$UUID /mnt/nvme ext4 defaults,nofail 0 2" >> /etc/fstab
  MODELS_DIR=/mnt/nvme/ollama
fi

mkdir -p "$MODELS_DIR"

# --- Install Ollama (NVIDIA drivers are already on this AMI) ---------------
# The installer creates a dedicated system user "ollama" that the service
# runs as, so the models dir must be owned by that user -- not ubuntu -- or
# the daemon fails to start with "permission denied" trying to create blobs/.
curl -fsSL https://ollama.com/install.sh | sh
chown -R ollama:ollama "$MODELS_DIR"

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_MODELS=$MODELS_DIR"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_CONTEXT_LENGTH=32768"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# Wait for the API to come up before pulling
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:11434/ > /dev/null && break
  sleep 2
done

# Default model: huihui_ai/qwen3-coder-next-abliterated:q4_K -- 52GB, 80B-A3B MoE,
# 256K context, explicitly tools-tagged. Needs the g6e.12xlarge's 192GB total
# VRAM (4x L40S) to load with no CPU offload -- on a single-GPU instance
# (48GB or less) it falls back to partial CPU offload, which is slow and can
# thrash if system RAM is also small (workable in principle since only ~3B
# params are active per token, but not recommended).
# https://ollama.com/huihui_ai/qwen3-coder-next-abliterated
#
# Lighter alternative (set var.ollama_model to use it, fits any single-GPU
# g6e instance): huihui_ai/qwen3-coder-abliterated:30b -- 19GB Q4_K_M,
# 30B-A3B MoE, 256K context. https://ollama.com/huihui_ai/qwen3-coder-abliterated
# Source weights: https://huggingface.co/huihui-ai
ollama pull "${ollama_model}"
