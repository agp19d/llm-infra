variable "region" {
  description = "AWS region to deploy the disposable environment into."
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = <<-EOT
    Your public IP address in /32 CIDR notation, e.g. 203.0.113.7/32.
    Find yours with: curl -s https://checkip.amazonaws.com
    RDP (3389) to the dev VM is locked to this address only. Required, no default.
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
    Default fits entirely in the g6e.xlarge's 48GB VRAM (single GPU, no offload).
  EOT
  type        = string
  default     = "huihui_ai/qwen3-coder-abliterated:30b"
}

variable "key_pair_name" {
  description = <<-EOT
    Name of an EXISTING EC2 key pair in var.region. Attached to the Windows dev VM so
    you can decrypt the initial Administrator password (aws ec2 get-password-data),
    and to the GPU instance for optional manual troubleshooting access.
  EOT
  type        = string
}
