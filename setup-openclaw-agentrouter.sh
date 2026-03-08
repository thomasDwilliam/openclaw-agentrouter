#!/bin/bash

# ============================================================
#  OpenClaw + AgentRouter Setup Script
#  GitHub: https://github.com/yourname/openclaw-agentrouter
#  Sets up OpenClaw with AgentRouter as the AI backend
#  using a local TLS proxy to bypass client fingerprinting
# ============================================================

set -e

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROXY_PORT=19999
PROXY_SCRIPT="/root/agentrouter-proxy.py"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"

# ── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║     OpenClaw + AgentRouter Setup Script       ║"
echo "  ║     Powered by DeepSeek via AgentRouter       ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Helper functions ─────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
ask()     { echo -e "${YELLOW}[?]${NC} $1"; }

# ── Step 1: Collect user inputs ───────────────────────────────
echo -e "${BOLD}── Step 1: Configuration ───────────────────────────────${NC}"
echo ""

# API Key
ask "Enter your AgentRouter API key (from https://agentrouter.org/console/token):"
read -r -s AGENT_API_KEY
echo ""
if [[ -z "$AGENT_API_KEY" ]]; then
  error "API key cannot be empty."
fi
success "API key received."
echo ""

# Model selection
echo -e "${CYAN}Available models on AgentRouter (common examples):${NC}"
echo "  1) deepseek-v3.2"
echo "  2) deepseek-v3.1"
echo "  3) deepseek-r1-0528"
echo "  4) glm-4.5"
echo "  5) glm-4.6"
echo "  6) Enter custom model ID"
echo ""
ask "Enter the number or type your exact model ID from your AgentRouter portal:"
read -r MODEL_CHOICE

case "$MODEL_CHOICE" in
  1) MODEL_ID="deepseek-v3.2" ;;
  2) MODEL_ID="deepseek-v3.1" ;;
  3) MODEL_ID="deepseek-r1-0528" ;;
  4) MODEL_ID="glm-4.5" ;;
  5) MODEL_ID="glm-4.6" ;;
  6|*)
    if [[ "$MODEL_CHOICE" =~ ^[1-6]$ ]]; then
      ask "Enter your custom model ID exactly as shown in your AgentRouter portal:"
      read -r MODEL_ID
    else
      MODEL_ID="$MODEL_CHOICE"
    fi
    ;;
esac

if [[ -z "$MODEL_ID" ]]; then
  error "Model ID cannot be empty."
fi
success "Model set to: ${BOLD}$MODEL_ID${NC}"
echo ""

# Context window
ask "Enter context window size (press Enter for default 128000):"
read -r CTX_INPUT
CONTEXT_WINDOW=${CTX_INPUT:-128000}
success "Context window: $CONTEXT_WINDOW tokens"
echo ""

# ── Step 2: Check / Install Node.js ──────────────────────────
echo -e "${BOLD}── Step 2: Checking Node.js ────────────────────────────${NC}"
echo ""

if command -v node &>/dev/null; then
  NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
  if [[ "$NODE_VER" -ge 22 ]]; then
    success "Node.js $(node -v) is installed and meets requirements (>=22)."
  else
    warn "Node.js $(node -v) is too old. Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &>/dev/null
    apt install -y nodejs &>/dev/null
    success "Node.js $(node -v) installed."
  fi
else
  info "Node.js not found. Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &>/dev/null
  apt install -y nodejs &>/dev/null
  success "Node.js $(node -v) installed."
fi
echo ""

# ── Step 3: Check / Install OpenClaw ─────────────────────────
echo -e "${BOLD}── Step 3: Checking OpenClaw ───────────────────────────${NC}"
echo ""

if command -v openclaw &>/dev/null; then
  success "OpenClaw is already installed: $(openclaw --version 2>/dev/null || echo 'version unknown')"
else
  info "OpenClaw not found. Installing..."
  npm install -g openclaw@latest
  success "OpenClaw installed successfully."
fi
echo ""

# ── Step 4: Install Python dependencies ──────────────────────
echo -e "${BOLD}── Step 4: Installing Python dependencies ──────────────${NC}"
echo ""

if ! command -v python3 &>/dev/null; then
  info "Python3 not found. Installing..."
  apt install -y python3 python3-pip &>/dev/null
fi

info "Installing required Python packages..."
pip install tls-client flask typing_extensions --break-system-packages -q
success "Python packages installed: tls-client, flask, typing_extensions"
echo ""

# ── Step 5: Create the TLS proxy script ──────────────────────
echo -e "${BOLD}── Step 5: Creating TLS proxy ──────────────────────────${NC}"
echo ""

cat > "$PROXY_SCRIPT" << 'PYEOF'
import tls_client
from flask import Flask, request, Response

app = Flask(__name__)

@app.route('/<path:path>', methods=['GET', 'POST', 'OPTIONS', 'PUT'])
def proxy(path):
    session = tls_client.Session(
        client_identifier="chrome_120",
        random_tls_extension_order=False
    )
    headers = {
        "Content-Type": "application/json",
        "Authorization": request.headers.get("Authorization", ""),
        "User-Agent": "Kilo-Code/5.10.0",
        "Referer": "https://kilocode.ai",
        "http-referer": "https://kilocode.ai",
        "x-title": "Kilo Code",
        "x-kilocode-version": "5.10.0",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "*",
        "sec-fetch-mode": "cors",
        "x-stainless-lang": "js",
        "x-stainless-package-version": "5.12.2",
        "x-stainless-os": "Linux",
        "x-stainless-arch": "x64",
        "x-stainless-runtime": "node",
        "x-stainless-runtime-version": "v22.21.1",
        "x-stainless-retry-count": "0",
    }

    # Always ensure /v1 prefix
    if not path.startswith("v1/"):
        path = "v1/" + path

    url = f"https://agentrouter.org/{path}"
    print(f"Proxying: {request.method} {url}", flush=True)

    if request.method == 'POST':
        resp = session.post(url, headers=headers, data=request.get_data())
    else:
        resp = session.get(url, headers=headers)

    print(f"Response status: {resp.status_code}", flush=True)
    content_type = resp.headers.get("content-type", "application/json")
    return Response(resp.content, status=resp.status_code, content_type=content_type)

if __name__ == '__main__':
    print("AgentRouter TLS Proxy running on http://127.0.0.1:19999", flush=True)
    app.run(host='127.0.0.1', port=19999)
PYEOF

success "Proxy script created at $PROXY_SCRIPT"
echo ""

# ── Step 6: Create systemd service ───────────────────────────
echo -e "${BOLD}── Step 6: Setting up systemd service ──────────────────${NC}"
echo ""

# Kill any existing process on the port
fuser -k ${PROXY_PORT}/tcp &>/dev/null || true
pkill -f agentrouter-proxy 2>/dev/null || true

cat > /etc/systemd/system/agentrouter-proxy.service << SVCEOF
[Unit]
Description=AgentRouter TLS Proxy for OpenClaw
After=network.target

[Service]
ExecStart=/usr/bin/python3 ${PROXY_SCRIPT}
Restart=always
RestartSec=3
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable agentrouter-proxy &>/dev/null
systemctl start agentrouter-proxy
sleep 2

if systemctl is-active --quiet agentrouter-proxy; then
  success "agentrouter-proxy service is running and enabled on boot."
else
  error "Failed to start agentrouter-proxy service. Run: journalctl -u agentrouter-proxy"
fi
echo ""

# ── Step 7: Test the proxy ────────────────────────────────────
echo -e "${BOLD}── Step 7: Testing proxy connection ────────────────────${NC}"
echo ""

info "Sending test request to AgentRouter via proxy..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  http://127.0.0.1:${PROXY_PORT}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_API_KEY" \
  -d "{\"model\": \"$MODEL_ID\", \"messages\": [{\"role\": \"user\", \"content\": \"say hi\"}], \"max_tokens\": 10}")

if [[ "$TEST_RESPONSE" == "200" ]]; then
  success "Proxy test passed! AgentRouter responded with HTTP 200."
else
  warn "Proxy returned HTTP $TEST_RESPONSE. Check your API key and model ID."
  warn "You can debug with: journalctl -u agentrouter-proxy -f"
fi
echo ""

# ── Step 8: Generate OpenClaw gateway token ───────────────────
echo -e "${BOLD}── Step 8: Creating OpenClaw config ────────────────────${NC}"
echo ""

mkdir -p "$HOME/.openclaw"

# Generate a random gateway token
GW_TOKEN=$(openssl rand -hex 24)

cat > "$OPENCLAW_CONFIG" << CFGEOF
{
  "meta": {
    "lastTouchedVersion": "2026.3.7"
  },
  "models": {
    "mode": "merge",
    "providers": {
      "custom-agentrouter-org": {
        "baseUrl": "http://127.0.0.1:${PROXY_PORT}",
        "apiKey": "${AGENT_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "${MODEL_ID}",
            "name": "${MODEL_ID} (AgentRouter)",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": ${CONTEXT_WINDOW},
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "custom-agentrouter-org/${MODEL_ID}"
      },
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "${GW_TOKEN}"
    }
  }
}
CFGEOF

success "OpenClaw config written to $OPENCLAW_CONFIG"
echo ""

# ── Done ──────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║           Setup Complete! 🦞                  ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}Model:${NC}    $MODEL_ID"
echo -e "  ${BOLD}Proxy:${NC}    http://127.0.0.1:${PROXY_PORT}"
echo -e "  ${BOLD}Config:${NC}   $OPENCLAW_CONFIG"
echo ""
echo -e "  ${CYAN}Start the gateway:${NC}"
echo -e "  ${BOLD}openclaw gateway${NC}"
echo ""
echo -e "  ${CYAN}Open the chat TUI:${NC}"
echo -e "  ${BOLD}openclaw tui${NC}"
echo ""
echo -e "  ${CYAN}Check proxy status:${NC}"
echo -e "  ${BOLD}systemctl status agentrouter-proxy${NC}"
echo ""
