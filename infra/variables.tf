variable "region" {
  description = "AWS region to deploy the disposable environment into."
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = <<-EOT
    Your public IP address in /32 CIDR notation, e.g. 203.0.113.7/32.
    Find yours with: curl -s https://checkip.amazonaws.com
    SSH (22) and the Ollama API (11434) on the GPU box are locked to this
    address only. Required, no default.
  EOT
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32")
    error_message = "my_ip must be a single IPv4 address in /32 CIDR notation, e.g. 203.0.113.7/32."
  }
}

variable "ollama_model" {
  description = <<-EOT
    Ollama model tag to pull on the GPU instance and configure in OpenCode.
    Default (24GB, 35B-A3B MoE) comfortably fits the g6e.xlarge's single
    L40S (48GB VRAM) with no CPU offload -- see the comment in
    userdata/gpu_init.sh.tpl before switching to a larger model/instance.
  EOT
  type        = string
  default     = "rafw007/Qwen3.6-35B-A3B-mlx-claude-coder-abliterated"
}

variable "key_pair_name" {
  description = <<-EOT
    Name of an EXISTING EC2 key pair in var.region. Attached to the GPU instance
    for SSH access (e.g. ssh -i /path/to/key.pem ubuntu@<gpu_public_ip>).
  EOT
  type        = string
}
