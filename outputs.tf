output "gpu_public_ip" {
  description = "Public IP of the GPU inference box (Ollama on :11434, SSH on :22, both reachable only from var.my_ip)."
  value       = aws_instance.gpu.public_ip
}

output "next_steps" {
  description = "How to point your local machine at the remote Ollama server."
  value       = <<-EOT
    GPU box is up at ${aws_instance.gpu.public_ip}. The model ("${var.ollama_model}") can
    take several minutes to pull after first boot -- if a request fails, wait and retry.

    Option A -- use the ollama CLI locally, pointed at the remote server:
        export OLLAMA_HOST=http://${aws_instance.gpu.public_ip}:11434
        ollama run ${var.ollama_model}

    Option B -- point any OpenAI-compatible client (OpenCode, etc.) at:
        http://${aws_instance.gpu.public_ip}:11434/v1

    Model weights live on the GPU box's ephemeral NVMe instance store and are
    wiped on stop/terminate (re-pulled automatically on next boot). Run
    `terraform destroy` when you're done to remove everything and stop billing.
  EOT
}
