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
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  # us-east-1a (2026-07-16) and us-east-1b (2026-07-16, later same day) both
  # hit Server.InsufficientInstanceCapacity for g6e.xlarge Spot -- switching
  # to on-demand above should make this rare, but if this AZ runs dry too,
  # try another index or drop the index and pick the AZ AWS's error message
  # names as available.
  availability_zone       = data.aws_availability_zones.available.names[2]
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
# No ingress rule anywhere allows 0.0.0.0/0. Both SSH and the Ollama API are
# locked to var.my_ip, so the GPU box is unreachable from anywhere but your
# own public IP.
# ---------------------------------------------------------------------------

resource "aws_security_group" "gpu" {
  name        = "gpu-sg"
  description = "GPU inference box: SSH and Ollama API from my IP only, all outbound"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "gpu-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "gpu_ssh" {
  security_group_id = aws_security_group.gpu.id
  description       = "SSH from my public IP only"
  cidr_ipv4         = var.my_ip
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "gpu_ollama" {
  security_group_id = aws_security_group.gpu.id
  description       = "Ollama API from my public IP only"
  cidr_ipv4         = var.my_ip
  from_port         = 11434
  to_port           = 11434
  ip_protocol       = "tcp"

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

# ---------------------------------------------------------------------------
# GPU inference instance (on-demand) -- Ollama serving the configured model.
# g6e.xlarge: 1x L40S / 48GB VRAM. The 24GB default model fits with headroom
# to spare -- this is the smallest g6e size, sized to the default model with
# no CPU offload; bump instance_type to a multi-GPU g6e size (e.g.
# g6e.12xlarge, 4x L40S / 192GB) if you switch var.ollama_model to something
# bigger (see userdata/gpu_init.sh.tpl). On-demand instead of Spot: g6e Spot
# capacity is thin enough per-AZ that Server.InsufficientInstanceCapacity was
# recurring across multiple AZs in the same day; on-demand draws from AWS's
# larger reserved capacity pool instead of Spot's leftover pool. Still a
# disposable box either way (dead-man switch below, weights re-pull on next
# boot).
# ---------------------------------------------------------------------------

resource "aws_instance" "gpu" {
  ami                    = data.aws_ssm_parameter.dlami_gpu.value
  instance_type          = "g6e.xlarge"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gpu.id]
  key_name               = var.key_pair_name

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/userdata/gpu_init.sh.tpl", {
    ollama_model = var.ollama_model
  })

  tags = merge(local.common_tags, { Name = "gpu-inference" })
}

# ---------------------------------------------------------------------------
# Dead-man switch -- stop the GPU instance 5h after apply if I forget to
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
    resources = [aws_instance.gpu.arn]
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
      InstanceIds = [aws_instance.gpu.id]
    })
  }
}
