#!/usr/bin/env bash

# ============================================================
#  OpenClaw + AgentRouter Setup Script
#  GitHub: https://github.com/yourname/openclaw-agentrouter
#  Supports: Linux (Debian/Ubuntu/RHEL/Arch) and macOS
#  Installation modes: System-wide | Docker
# ============================================================

set -e

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROXY_PORT=19999

# ── Detect OS ────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="macos" ;;
    *)       error "Unsupported OS: $(uname -s)" ;;
  esac

  if [[ "$OS" == "linux" ]]; then
    if   [[ -f /etc/debian_version ]]; then DISTRO="debian"
    elif [[ -f /etc/redhat-release ]]; then DISTRO="redhat"
    elif [[ -f /etc/arch-release ]];   then DISTRO="arch"
    else                                    DISTRO="unknown"
    fi
  fi
}

# ── Helper functions ─────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
ask()     { echo -e "${YELLOW}[?]${NC} $1"; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "System-wide installation requires root. Please run with sudo."
  fi
}

# ── Banner ───────────────────────────────────────────────────
print_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║     OpenClaw + AgentRouter Setup Script       ║"
  echo "  ║     Powered by Thomas William                 ║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ── Installation mode selection ──────────────────────────────
select_install_mode() {
  echo -e "${BOLD}── Installation Mode ───────────────────────────────────${NC}"
  echo ""
  echo "  1) System-wide  – Install Node.js, Python, OpenClaw natively"
  echo "  2) Docker        – Run everything inside a Docker container"
  echo ""
  ask "Choose installation mode [1/2]:"
  read -r MODE_CHOICE
  case "$MODE_CHOICE" in
    1) INSTALL_MODE="system" ;;
    2) INSTALL_MODE="docker" ;;
    *) error "Invalid choice. Please enter 1 or 2." ;;
  esac
  echo ""
}

# ── Collect user inputs ──────────────────────────────────────
collect_inputs() {
  echo -e "${BOLD}── Configuration ───────────────────────────────────────${NC}"
  echo ""

  ask "Enter your AgentRouter API key (from https://agentrouter.org/console/token):"
  read -r -s AGENT_API_KEY
  echo ""
  [[ -z "$AGENT_API_KEY" ]] && error "API key cannot be empty."
  success "API key received."
  echo ""

  echo -e "${CYAN}Available models on AgentRouter:${NC}"
  echo "  1) deepseek-v3.2"
  echo "  2) deepseek-v3.1"
  echo "  3) deepseek-r1-0528"
  echo "  4) glm-4.5"
  echo "  5) glm-4.6"
  echo "  6) claude-haiku-4-5-20251001"
  echo "  7) claude-opus-4-6"
  echo "  8) Enter custom model ID"
  echo ""
  ask "Enter the number or type your exact model ID:"
  read -r MODEL_CHOICE

  case "$MODEL_CHOICE" in
    1) MODEL_ID="deepseek-v3.2" ;;
    2) MODEL_ID="deepseek-v3.1" ;;
    3) MODEL_ID="deepseek-r1-0528" ;;
    4) MODEL_ID="glm-4.5" ;;
    5) MODEL_ID="glm-4.6" ;;
    6) MODEL_ID="claude-haiku-4-5-20251001" ;;
    7) MODEL_ID="claude-opus-4-6" ;;
    *)
      if [[ "$MODEL_CHOICE" =~ ^[1-8]$ ]]; then
        ask "Enter your custom model ID exactly as shown in your AgentRouter portal:"
        read -r MODEL_ID
      else
        MODEL_ID="$MODEL_CHOICE"
      fi
      ;;
  esac

  [[ -z "$MODEL_ID" ]] && error "Model ID cannot be empty."
  success "Model set to: ${BOLD}$MODEL_ID${NC}"
  echo ""

  ask "Enter context window size (press Enter for default 128000):"
  read -r CTX_INPUT
  CONTEXT_WINDOW=${CTX_INPUT:-128000}
  success "Context window: $CONTEXT_WINDOW tokens"
  echo ""
}

# ════════════════════════════════════════════════════════════
#  SYSTEM-WIDE INSTALLATION
# ════════════════════════════════════════════════════════════

install_node_system() {
  echo -e "${BOLD}── Checking Node.js ────────────────────────────────────${NC}"
  echo ""
  if command -v node &>/dev/null; then
    NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
    if [[ "$NODE_VER" -ge 22 ]]; then
      success "Node.js $(node -v) meets requirements (>=22)."
      echo ""; return
    fi
    warn "Node.js $(node -v) is too old. Upgrading to v22..."
  else
    info "Node.js not found. Installing v22..."
  fi

  case "$OS" in
    macos)
      if ! command -v brew &>/dev/null; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      brew install node@22
      brew link --overwrite node@22
      ;;
    linux)
      case "$DISTRO" in
        debian)
          curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &>/dev/null
          apt-get install -y nodejs &>/dev/null
          ;;
        redhat)
          curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - &>/dev/null
          yum install -y nodejs &>/dev/null
          ;;
        arch)
          pacman -Sy --noconfirm nodejs npm &>/dev/null
          ;;
        *)
          error "Unsupported Linux distro. Please install Node.js 22 manually."
          ;;
      esac
      ;;
  esac
  success "Node.js $(node -v) installed."
  echo ""
}

install_python_system() {
  echo -e "${BOLD}── Installing Python dependencies ──────────────────────${NC}"
  echo ""

  if ! command -v python3 &>/dev/null; then
    info "Python3 not found. Installing..."
    case "$OS" in
      macos)  brew install python3 ;;
      linux)
        case "$DISTRO" in
          debian) apt-get install -y python3 python3-pip &>/dev/null ;;
          redhat) yum install -y python3 python3-pip &>/dev/null ;;
          arch)   pacman -Sy --noconfirm python python-pip &>/dev/null ;;
        esac
        ;;
    esac
  fi

  info "Installing required Python packages..."
  if [[ "$OS" == "macos" ]]; then
    pip3 install tls-client flask typing_extensions -q
  else
    pip install tls-client flask typing_extensions --break-system-packages -q 2>/dev/null || \
    pip3 install tls-client flask typing_extensions -q
  fi
  success "Python packages installed: tls-client, flask, typing_extensions"
  echo ""
}

install_openclaw_system() {
  echo -e "${BOLD}── Checking OpenClaw ───────────────────────────────────${NC}"
  echo ""
  if command -v openclaw &>/dev/null; then
    success "OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'version unknown')"
  else
    info "Installing OpenClaw..."
    npm install -g openclaw@latest
    success "OpenClaw installed."
  fi
  echo ""
}

create_proxy_script_system() {
  echo -e "${BOLD}── Creating TLS proxy ──────────────────────────────────${NC}"
  echo ""

  if [[ "$OS" == "macos" ]]; then
    PROXY_SCRIPT="$HOME/agentrouter-proxy.py"
  else
    PROXY_SCRIPT="/root/agentrouter-proxy.py"
  fi

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
}

setup_service_system() {
  echo -e "${BOLD}── Setting up proxy service ────────────────────────────${NC}"
  echo ""

  PYTHON_BIN=$(command -v python3 || command -v python)

  if [[ "$OS" == "macos" ]]; then
    # macOS: use launchd plist
    PLIST_PATH="$HOME/Library/LaunchAgents/org.agentrouter.proxy.plist"
    cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>org.agentrouter.proxy</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>$PROXY_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/agentrouter-proxy.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/agentrouter-proxy.err</string>
</dict>
</plist>
PLISTEOF
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load -w "$PLIST_PATH"
    sleep 2
    if launchctl list | grep -q "org.agentrouter.proxy"; then
      success "agentrouter-proxy LaunchAgent is running and enabled on login."
    else
      warn "LaunchAgent may not have started. Check /tmp/agentrouter-proxy.err"
    fi
  else
    # Linux: use systemd
    fuser -k ${PROXY_PORT}/tcp &>/dev/null || true
    pkill -f agentrouter-proxy 2>/dev/null || true

    cat > /etc/systemd/system/agentrouter-proxy.service << SVCEOF
[Unit]
Description=AgentRouter TLS Proxy for OpenClaw
After=network.target

[Service]
ExecStart=$PYTHON_BIN $PROXY_SCRIPT
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
      error "Failed to start agentrouter-proxy. Run: journalctl -u agentrouter-proxy"
    fi
  fi
  echo ""
}

test_proxy_system() {
  echo -e "${BOLD}── Testing proxy connection ────────────────────────────${NC}"
  echo ""
  info "Sending test request via proxy..."
  TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    http://127.0.0.1:${PROXY_PORT}/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_API_KEY" \
    -d "{\"model\": \"$MODEL_ID\", \"messages\": [{\"role\": \"user\", \"content\": \"say hi\"}], \"max_tokens\": 10}")
  if [[ "$TEST_RESPONSE" == "200" ]]; then
    success "Proxy test passed! AgentRouter responded with HTTP 200."
  else
    warn "Proxy returned HTTP $TEST_RESPONSE. Check your API key and model ID."
    [[ "$OS" == "linux" ]] && warn "Debug: journalctl -u agentrouter-proxy -f"
    [[ "$OS" == "macos" ]] && warn "Debug: cat /tmp/agentrouter-proxy.err"
  fi
  echo ""
}

write_openclaw_config() {
  echo -e "${BOLD}── Writing OpenClaw config ─────────────────────────────${NC}"
  echo ""
  OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
  mkdir -p "$HOME/.openclaw"
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
}

start_openclaw_gateway_system() {
  echo -e "${BOLD}── Starting OpenClaw gateway ───────────────────────────${NC}"
  echo ""
  openclaw gateway install 2>/dev/null || true

  if [[ "$OS" == "macos" ]]; then
    # Try user-level launchd service, fall back to background process
    openclaw gateway start 2>/dev/null || \
      nohup openclaw gateway > /tmp/openclaw-gateway.log 2>&1 &
  else
    systemctl --user start openclaw-gateway.service 2>/dev/null || true
    if ! systemctl --user is-active --quiet openclaw-gateway.service 2>/dev/null; then
      loginctl enable-linger root 2>/dev/null || true
      nohup openclaw gateway > /tmp/openclaw-gateway.log 2>&1 &
    fi
  fi

  sleep 3
  if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
    success "OpenClaw gateway started."
  else
    warn "Could not auto-start gateway. Run manually: openclaw gateway"
  fi
  echo ""
}

run_system_install() {
  require_root
  detect_os
  collect_inputs
  install_node_system
  install_openclaw_system
  install_python_system
  create_proxy_script_system
  setup_service_system
  test_proxy_system
  write_openclaw_config
  start_openclaw_gateway_system
}

# ════════════════════════════════════════════════════════════
#  DOCKER INSTALLATION
# ════════════════════════════════════════════════════════════

check_install_docker() {
  echo -e "${BOLD}── Checking Docker ─────────────────────────────────────${NC}"
  echo ""

  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    success "Docker is installed and running: $(docker --version)"
    echo ""; return
  fi

  if command -v docker &>/dev/null; then
    warn "Docker is installed but not running. Attempting to start..."
    if [[ "$OS" == "linux" ]]; then
      systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
      sleep 3
      if docker info &>/dev/null 2>&1; then
        success "Docker started successfully."
        echo ""; return
      fi
    fi
    error "Docker daemon is not running. Please start Docker and re-run this script."
  fi

  warn "Docker not found. Installing Docker..."

  case "$OS" in
    macos)
      error "On macOS, please install Docker Desktop manually from https://www.docker.com/products/docker-desktop and re-run this script."
      ;;
    linux)
      case "$DISTRO" in
        debian)
          apt-get update -qq
          apt-get install -y ca-certificates curl gnupg lsb-release &>/dev/null
          install -m 0755 -d /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
          chmod a+r /etc/apt/keyrings/docker.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
            $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
          apt-get update -qq
          apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
          ;;
        redhat)
          yum install -y yum-utils &>/dev/null
          yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &>/dev/null
          yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
          ;;
        arch)
          pacman -Sy --noconfirm docker &>/dev/null
          ;;
        *)
          error "Unsupported Linux distro for automatic Docker install. Please install Docker manually."
          ;;
      esac

      systemctl enable docker &>/dev/null
      systemctl start docker
      sleep 3

      if docker info &>/dev/null 2>&1; then
        success "Docker installed and running: $(docker --version)"
      else
        error "Docker installed but failed to start. Check: systemctl status docker"
      fi
      ;;
  esac
  echo ""
}

run_docker_install() {
  detect_os
  [[ "$OS" == "linux" ]] && [[ "$EUID" -ne 0 ]] && error "Docker installation on Linux requires root. Please run with sudo."
  collect_inputs
  check_install_docker

  WORK_DIR="$HOME/.openclaw-docker"
  mkdir -p "$WORK_DIR"

  echo -e "${BOLD}── Creating Docker setup files ─────────────────────────${NC}"
  echo ""

  # Write proxy script
  cat > "$WORK_DIR/agentrouter-proxy.py" << 'PYEOF'
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
    app.run(host='0.0.0.0', port=19999)
PYEOF

  # Generate gateway token
  GW_TOKEN=$(openssl rand -hex 24 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(24))")
  OPENCLAW_CONFIG="$WORK_DIR/openclaw.json"

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
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
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

  # Write Dockerfile
  cat > "$WORK_DIR/Dockerfile" << 'DOCKEREOF'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y \
    curl ca-certificates python3 python3-pip openssl \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# Python packages
RUN pip install tls-client flask typing_extensions --break-system-packages -q

# OpenClaw
RUN npm install -g openclaw@latest

# Copy files
COPY agentrouter-proxy.py /app/agentrouter-proxy.py
COPY openclaw.json /root/.openclaw/openclaw.json
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

WORKDIR /app
EXPOSE 19999

ENTRYPOINT ["/app/entrypoint.sh"]
DOCKEREOF

  # Write entrypoint
  cat > "$WORK_DIR/entrypoint.sh" << 'ENTEOF'
#!/bin/bash
set -e

echo "[Entrypoint] Starting AgentRouter TLS Proxy..."
python3 /app/agentrouter-proxy.py &
PROXY_PID=$!

sleep 2

echo "[Entrypoint] Starting OpenClaw gateway..."
openclaw gateway install 2>/dev/null || true
openclaw gateway &
GW_PID=$!

echo "[Entrypoint] All services started."
echo "  Proxy PID:   $PROXY_PID"
echo "  Gateway PID: $GW_PID"

# Keep container alive; exit if either process dies
wait -n $PROXY_PID $GW_PID
ENTEOF
  chmod +x "$WORK_DIR/entrypoint.sh"

  success "Docker setup files created in $WORK_DIR"
  echo ""

  # Build Docker image
  echo -e "${BOLD}── Building Docker image ───────────────────────────────${NC}"
  echo ""
  info "Building openclaw-agentrouter image (this may take a few minutes)..."
  docker build -t openclaw-agentrouter "$WORK_DIR"
  success "Docker image built: openclaw-agentrouter"
  echo ""

  # Stop any existing container
  docker rm -f openclaw-agentrouter 2>/dev/null || true

  # Run container
  echo -e "${BOLD}── Starting Docker container ───────────────────────────${NC}"
  echo ""
  docker run -d \
    --name openclaw-agentrouter \
    --restart unless-stopped \
    -p ${PROXY_PORT}:${PROXY_PORT} \
    openclaw-agentrouter

  sleep 4

  if docker ps --filter "name=openclaw-agentrouter" --filter "status=running" | grep -q openclaw; then
    success "Container openclaw-agentrouter is running."
  else
    warn "Container may not be running. Check: docker logs openclaw-agentrouter"
  fi
  echo ""

  # Test proxy
  echo -e "${BOLD}── Testing proxy connection ────────────────────────────${NC}"
  echo ""
  info "Sending test request via proxy (port ${PROXY_PORT})..."
  TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    http://127.0.0.1:${PROXY_PORT}/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_API_KEY" \
    -d "{\"model\": \"$MODEL_ID\", \"messages\": [{\"role\": \"user\", \"content\": \"say hi\"}], \"max_tokens\": 10}")
  if [[ "$TEST_RESPONSE" == "200" ]]; then
    success "Proxy test passed! AgentRouter responded with HTTP 200."
  else
    warn "Proxy returned HTTP $TEST_RESPONSE. Check: docker logs openclaw-agentrouter"
  fi
  echo ""
}

# ── Print summary ─────────────────────────────────────────────
print_summary() {
  echo -e "${GREEN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║           Setup Complete! 🦞                  ║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}Mode:${NC}     $INSTALL_MODE"
  echo -e "  ${BOLD}Model:${NC}    $MODEL_ID"
  echo -e "  ${BOLD}Proxy:${NC}    http://127.0.0.1:${PROXY_PORT}"

  if [[ "$INSTALL_MODE" == "system" ]]; then
    echo -e "  ${BOLD}Config:${NC}   $HOME/.openclaw/openclaw.json"
    echo ""
    echo -e "  ${CYAN}Open chat TUI:${NC}    ${BOLD}openclaw tui${NC}"
    echo -e "  ${CYAN}Check gateway:${NC}    ${BOLD}openclaw health${NC}"
    if [[ "$OS" == "linux" ]]; then
      echo -e "  ${CYAN}Check proxy:${NC}      ${BOLD}systemctl status agentrouter-proxy${NC}"
    else
      echo -e "  ${CYAN}Check proxy log:${NC}  ${BOLD}cat /tmp/agentrouter-proxy.log${NC}"
    fi
  else
    echo -e "  ${BOLD}Config:${NC}   $HOME/.openclaw-docker/openclaw.json"
    echo ""
    echo -e "  ${CYAN}Container logs:${NC}   ${BOLD}docker logs -f openclaw-agentrouter${NC}"
    echo -e "  ${CYAN}Stop container:${NC}   ${BOLD}docker stop openclaw-agentrouter${NC}"
    echo -e "  ${CYAN}Restart:${NC}          ${BOLD}docker restart openclaw-agentrouter${NC}"
  fi
  echo ""
}

# ── Main ──────────────────────────────────────────────────────
print_banner
select_install_mode

if [[ "$INSTALL_MODE" == "system" ]]; then
  run_system_install
else
  run_docker_install
fi

print_summary
