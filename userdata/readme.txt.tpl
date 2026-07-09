=============================================================================
 DISPOSABLE DEV ENVIRONMENT
=============================================================================

This VM and the GPU box are EPHEMERAL. Nothing here survives
`terraform destroy` -- no snapshots, no S3, no EFS, no Elastic IPs. The
ONLY thing that persists between sessions is whatever you have pushed to
GitHub. Commit and push before you destroy, or the work is gone for good.

-----------------------------------------------------------------------------
1. Test the Ollama endpoint on the GPU box
-----------------------------------------------------------------------------
    curl http://${gpu_private_ip}:11434/v1/models

You should see JSON listing "${ollama_model}". The model is pulled by the
GPU box's own boot script and can take several minutes after first boot --
if you get a connection error, wait and retry.

-----------------------------------------------------------------------------
2. Launch OpenCode
-----------------------------------------------------------------------------
OpenCode is already installed, with a provider pre-configured at:
    C:\Users\Administrator\.config\opencode\opencode.json
    -> baseURL http://${gpu_private_ip}:11434/v1
    -> model   ${ollama_model}

From a terminal, cd into your project directory and run:
    opencode

-----------------------------------------------------------------------------
3. Connect to GitHub
-----------------------------------------------------------------------------
No GitHub credentials are stored anywhere in this environment (not in
Terraform, not in user_data, not in state). Pick ONE option, every session:

  Option A -- GitHub CLI (installed via Chocolatey):
      gh auth login
      git config --global user.name  "Your Name"
      git config --global user.email "you@example.com"

  Option B -- SSH key:
      ssh-keygen -t ed25519 -C "you@example.com"
      Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | clip
    Paste it into https://github.com/settings/keys, then clone/push over SSH.

-----------------------------------------------------------------------------
4. BEFORE YOU RUN `terraform destroy`
-----------------------------------------------------------------------------
  *** PUSH ALL WORK TO GITHUB FIRST. ***
  Everything on this VM and the GPU box, including any downloaded model
  weights, is destroyed permanently and unrecoverably.

-----------------------------------------------------------------------------
5. Dead-man switch (in case you forget)
-----------------------------------------------------------------------------
Both this VM and the GPU box are AUTOMATICALLY STOPPED (not destroyed)
5 hours after `terraform apply`. STOPPED IS NOT DESTROYED -- you are still
being billed for EBS storage on both boxes until you run `terraform destroy`.

The GPU box is a Spot instance with model weights on its local NVMe
instance store. Stopping it (or a Spot interruption) WIPES those weights --
that's expected and fine, they just get re-pulled ("${ollama_model}") the
next time the box boots.

-----------------------------------------------------------------------------
6. Windows Administrator password
-----------------------------------------------------------------------------
You're already RDP'd in if you're reading this, but for future reference:
find this instance's ID (EC2 console, or from your own machine run
`terraform output`), then decrypt the password locally with your private
key for key pair "${key_pair_name}":

    aws ec2 get-password-data --instance-id <this-instance-id> \
        --priv-launch-key /path/to/${key_pair_name}.pem

Run `terraform destroy` when you're done to remove everything and stop
billing.
