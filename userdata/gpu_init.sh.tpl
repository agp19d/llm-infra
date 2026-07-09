#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# --- Format and mount the local NVMe instance store at /mnt/nvme -----------
# Model weights live here, not on the EBS root disk: it's free, fast, and its
# contents vanish on stop/terminate/spot-interruption, which is exactly what
# we want for a disposable box (weights just get re-pulled next boot).
NVME_LINK=$$(ls /dev/disk/by-id/ | grep -m1 'Amazon_EC2_NVMe_Instance_Storage')
NVME_DEV=$$(readlink -f "/dev/disk/by-id/$$NVME_LINK")

mkfs.ext4 -F "$$NVME_DEV"
mkdir -p /mnt/nvme
mount "$$NVME_DEV" /mnt/nvme
UUID=$$(blkid -s UUID -o value "$$NVME_DEV")
echo "UUID=$$UUID /mnt/nvme ext4 defaults,nofail 0 2" >> /etc/fstab

mkdir -p /mnt/nvme/ollama
chown -R $$(logname 2>/dev/null || echo ubuntu):$$(logname 2>/dev/null || echo ubuntu) /mnt/nvme/ollama || true

# --- Install Ollama (NVIDIA drivers are already on this AMI) ---------------
curl -fsSL https://ollama.com/install.sh | sh

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_MODELS=/mnt/nvme/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_CONTEXT_LENGTH=32768"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# Wait for the API to come up before pulling
for i in $$(seq 1 30); do
  curl -sf http://127.0.0.1:11434/ > /dev/null && break
  sleep 2
done

# Default model: huihui_ai/qwen3-coder-abliterated:30b -- 19GB Q4_K_M, 30B-A3B MoE,
# 256K context. Fits entirely in the g6e.xlarge's single 48GB-VRAM GPU (L40S).
# https://ollama.com/huihui_ai/qwen3-coder-abliterated
#
# Stronger alternative (not the default -- set var.ollama_model to use it):
# huihui_ai/qwen3-coder-next-abliterated:q4_K -- 52GB, 80B-A3B MoE, 256K context,
# explicitly tools-tagged. https://ollama.com/huihui_ai/qwen3-coder-next-abliterated
# It exceeds 48GB VRAM, so it needs either partial CPU offload (slower, but workable
# since only ~3B params are active per token) or a bigger instance (g6e.12xlarge, 4x
# L40S / 192GB VRAM). Source weights: https://huggingface.co/huihui-ai
ollama pull "${ollama_model}"
