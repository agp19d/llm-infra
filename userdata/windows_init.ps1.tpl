<powershell>
$ErrorActionPreference = "Stop"
Start-Transcript -Path C:\Windows\Temp\user-data.log -Append

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

# --- Chocolatey, then Git for Windows / Node.js LTS / GitHub CLI -----------
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

$env:Path = "$env:Path;C:\ProgramData\chocolatey\bin"

choco install -y git nodejs-lts gh

$env:Path = "$env:Path;C:\Program Files\nodejs;C:\Program Files\Git\cmd"

# --- OpenCode ---------------------------------------------------------------
npm install -g opencode-ai

$configDir = "C:\Users\Administrator\.config\opencode"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$opencodeConfig = @'
${opencode_config_json}
'@
Set-Content -Path "$configDir\opencode.json" -Value $opencodeConfig -Encoding utf8

# --- Desktop README ----------------------------------------------------------
$readme = @'
${readme_txt}
'@
Set-Content -Path "C:\Users\Administrator\Desktop\README.txt" -Value $readme -Encoding utf8

Stop-Transcript
</powershell>
