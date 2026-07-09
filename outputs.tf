output "windows_public_ip" {
  description = "Public IP of the Windows dev VM (RDP here, from var.my_ip only)."
  value       = aws_instance.windows.public_ip
}

output "gpu_private_ip" {
  description = "Private IP of the GPU inference box (Ollama on :11434, reachable only from dev-sg)."
  value       = aws_instance.gpu.private_ip
}

output "next_steps" {
  description = "One-line reminder of what to do next."
  value       = "RDP to ${aws_instance.windows.public_ip}:3389 (decrypt the password with: aws ec2 get-password-data --instance-id ${aws_instance.windows.id} --priv-launch-key /path/to/${var.key_pair_name}.pem), read Desktop\\README.txt, then run opencode -- and push everything to GitHub before you run terraform destroy."
}
