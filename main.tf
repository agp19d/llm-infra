locals {
  common_tags = {
    Project = "disposable-dev"
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "disposable-dev-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "disposable-dev-public" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "disposable-dev-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "disposable-dev-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security groups
#
# No ingress rule anywhere allows 0.0.0.0/0. RDP is locked to var.my_ip, and
# the Ollama port is locked to traffic originating from dev-sg specifically
# (not a CIDR), so the GPU box is unreachable from anywhere but the dev VM.
# ---------------------------------------------------------------------------

resource "aws_security_group" "dev" {
  name        = "dev-sg"
  description = "Windows dev VM: RDP from my IP only, all outbound"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "dev-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "dev_rdp" {
  security_group_id = aws_security_group.dev.id
  description       = "RDP from my public IP only"
  cidr_ipv4         = var.my_ip
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "dev_all_out" {
  security_group_id = aws_security_group.dev.id
  description       = "Allow all outbound (needed for GitHub over 443/22, package installs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.common_tags
}

resource "aws_security_group" "gpu" {
  name        = "gpu-sg"
  description = "GPU inference box: Ollama API reachable from dev-sg only, all outbound"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "gpu-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "gpu_ollama" {
  security_group_id            = aws_security_group.gpu.id
  description                  = "Ollama API from dev-sg only"
  referenced_security_group_id = aws_security_group.dev.id
  from_port                    = 11434
  to_port                      = 11434
  ip_protocol                  = "tcp"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "gpu_all_out" {
  security_group_id = aws_security_group.gpu.id
  description       = "Allow all outbound (model pulls, package installs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# AMIs -- resolved via AWS's published SSM parameters so we always get the
# latest build without guessing at name-filter wildcards.
# https://docs.aws.amazon.com/dlami/latest/devguide/find-dlami-id.html
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "dlami_gpu" {
  name = "/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-22.04/latest/ami-id"
}

data "aws_ssm_parameter" "windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

# ---------------------------------------------------------------------------
# GPU inference instance (Spot) -- Ollama serving the configured model
# ---------------------------------------------------------------------------

resource "aws_instance" "gpu" {
  ami                    = data.aws_ssm_parameter.dlami_gpu.value
  instance_type          = "g6e.xlarge"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gpu.id]
  key_name               = var.key_pair_name

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  root_block_device {
    volume_size           = 60
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/userdata/gpu_init.sh.tpl", {
    ollama_model = var.ollama_model
  })

  tags = merge(local.common_tags, { Name = "gpu-inference" })
}

# ---------------------------------------------------------------------------
# Windows dev VM -- OpenCode pointed at the GPU box's private IP
# ---------------------------------------------------------------------------

locals {
  opencode_config_json = templatefile("${path.module}/userdata/opencode.json.tpl", {
    gpu_private_ip = aws_instance.gpu.private_ip
    ollama_model   = var.ollama_model
  })

  desktop_readme_txt = templatefile("${path.module}/userdata/readme.txt.tpl", {
    gpu_private_ip = aws_instance.gpu.private_ip
    ollama_model   = var.ollama_model
    key_pair_name  = var.key_pair_name
  })

  windows_user_data = templatefile("${path.module}/userdata/windows_init.ps1.tpl", {
    opencode_config_json = local.opencode_config_json
    readme_txt           = local.desktop_readme_txt
  })
}

resource "aws_instance" "windows" {
  ami                    = data.aws_ssm_parameter.windows.value
  instance_type          = "t3.xlarge"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.dev.id]
  key_name               = var.key_pair_name

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = local.windows_user_data

  tags = merge(local.common_tags, { Name = "windows-dev" })
}

# ---------------------------------------------------------------------------
# Dead-man switch -- stop both instances 5h after apply if I forget to
# destroy. Uses EventBridge Scheduler (the successor to plain EventBridge
# cron rules) for an exact one-shot firing rather than a recurring rule,
# which is a better fit for "N hours after launch". The schedule itself is
# a normal Terraform-managed resource, so `terraform destroy` removes it
# (fired or not) along with everything else -- no orphans either way.
# time_static freezes the apply timestamp in state so re-running `plan`
# doesn't show a perpetual diff from a fresh timestamp() every time.
# ---------------------------------------------------------------------------

resource "time_static" "deploy" {}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "disposable-dev-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "scheduler_stop_instances" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:StopInstances"]
    resources = [aws_instance.gpu.arn, aws_instance.windows.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_stop_instances" {
  name   = "stop-instances"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_stop_instances.json
}

resource "aws_scheduler_schedule" "dead_man_switch" {
  name       = "disposable-dev-dead-man-switch"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "at(${formatdate("YYYY-MM-DD'T'hh:mm:ss", timeadd(time_static.deploy.rfc3339, "5h"))})"
  schedule_expression_timezone = "UTC"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      InstanceIds = [aws_instance.gpu.id, aws_instance.windows.id]
    })
  }
}
