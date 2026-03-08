# 🦞 openclaw-agentrouter

> One-click setup script to connect [OpenClaw](https://openclaw.ai) with [AgentRouter](https://agentrouter.org) — a free DeepSeek API proxy — using a local TLS spoof to bypass client fingerprinting.

---

## 🧠 What is this?

[AgentRouter](https://agentrouter.org/register?aff=GD9A) is a **free public AI gateway** that provides access to DeepSeek models (v3.2, v3.1, R1, etc.) and other LLMs at no cost. It was originally built for tools like KiloCode, RooCode, and OpenAI Codex.

[OpenClaw](https://openclaw.ai) is a powerful agentic AI shell that supports custom model providers — but AgentRouter blocks requests from unrecognized clients using **TLS fingerprinting**.

This script solves that by:
- Running a **local Python proxy** that spoofs a KiloCode TLS fingerprint
- Configuring OpenClaw to route all requests through the proxy
- Setting everything up as a **systemd service** so it survives reboots

---

## ✅ Requirements

- Ubuntu / Debian Linux (tested on Ubuntu 24)
- Root access
- A free AgentRouter API key → [agentrouter.org/console/token](https://agentrouter.org/console/token)

---

## 🚀 Quick Start

```bash
git clone https://github.com/thomasDwilliam/openclaw-agentrouter.git
cd openclaw-agentrouter
chmod +x setup-openclaw-agentrouter.sh
sudo ./setup-openclaw-agentrouter.sh
```

The script will interactively ask you for:
- Your AgentRouter API key
- Your preferred model (from a menu or custom input)
- Context window size (default: 128,000 tokens)

---

## 📋 What the script installs

| Component | Details |
|---|---|
| Node.js 22+ | Required by OpenClaw |
| OpenClaw | Latest version via npm |
| Python packages | `tls-client`, `flask`, `typing_extensions` |
| TLS Proxy | `/root/agentrouter-proxy.py` on port `19999` |
| Systemd service | `agentrouter-proxy.service` (auto-starts on boot) |
| OpenClaw config | `~/.openclaw/openclaw.json` |

---

## 🎮 Available Models

Models available on AgentRouter (check your portal for the full list):

| Model ID | Description |
|---|---|
| `deepseek-v3.2` | DeepSeek V3.2 — latest, recommended |
| `deepseek-v3.1` | DeepSeek V3.1 |
| `deepseek-r1-0528` | DeepSeek R1 reasoning model |
| `glm-4.5` | Zhipu GLM-4.5 |
| `glm-4.6` | Zhipu GLM-4.6 |

> You can also enter any custom model ID from your [AgentRouter dashboard](https://agentrouter.org/console/token).

---

## 🔧 How it works

AgentRouter only accepts requests from whitelisted clients (KiloCode, RooCode, Codex). It detects clients using **TLS fingerprinting** — not just headers — so simply adding a `User-Agent` header isn't enough.

This script runs a local Flask proxy using [`tls-client`](https://github.com/FlorianREGAZ/Python-Tls-Client) which spoofs a Chrome 120 / KiloCode TLS fingerprint and injects the required headers:

```
User-Agent: Kilo-Code/5.10.0
http-referer: https://kilocode.ai
x-title: Kilo Code
x-kilocode-version: 5.10.0
```

OpenClaw is then configured to send all requests to `http://127.0.0.1:19999` instead of AgentRouter directly.

```
OpenClaw → localhost:19999 (TLS proxy) → agentrouter.org → DeepSeek
```

---

## 🖥️ Usage

After setup, start the OpenClaw gateway and open the TUI:

```bash
# Start the gateway (keep running in one terminal)
openclaw gateway

# Open the chat interface (in another terminal)
openclaw tui
```

---

## 🔍 Troubleshooting

**Check proxy status:**
```bash
systemctl status agentrouter-proxy
journalctl -u agentrouter-proxy -f
```

**Restart proxy:**
```bash
systemctl restart agentrouter-proxy
```

**Test proxy manually:**
```bash
curl http://127.0.0.1:19999/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR-API-KEY" \
  -d '{"model": "deepseek-v3.2", "messages": [{"role": "user", "content": "say hi"}], "max_tokens": 10}'
```

**Re-run setup (to change model or API key):**
```bash
sudo ./setup-openclaw-agentrouter.sh
```

---

## ⚠️ Disclaimer

This project is not affiliated with AgentRouter, OpenClaw, or Anthropic. AgentRouter is a third-party free service — use it responsibly and respect their [terms of service](https://agentrouter.org). The TLS spoofing technique is used purely to identify as a supported client.

---

## 📄 License

MIT
