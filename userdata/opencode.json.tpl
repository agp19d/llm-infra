{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local-gpu": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local GPU (Ollama)",
      "options": {
        "baseURL": "http://${gpu_private_ip}:11434/v1"
      },
      "models": {
        "${ollama_model}": {
          "name": "${ollama_model}"
        }
      }
    }
  }
}
