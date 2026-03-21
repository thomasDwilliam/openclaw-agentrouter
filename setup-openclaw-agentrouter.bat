@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

:: ============================================================
::  OpenClaw + AgentRouter Setup Script  (Windows)
::  GitHub: https://github.com/yourname/openclaw-agentrouter
::  Supports: Windows 10/11
::  Installation modes: System-wide | Docker
:: ============================================================

:: ── Check Administrator ──────────────────────────────────────
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as Administrator.
    echo Right-click the script and choose "Run as administrator".
    pause
    exit /b 1
)

:: ── Colors via ANSI (Windows 10+) ───────────────────────────
:: Enable virtual terminal processing
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1

set "CYAN=[36m"
set "GREEN=[32m"
set "YELLOW=[33m"
set "RED=[31m"
set "BOLD=[1m"
set "NC=[0m"
set "PROXY_PORT=19999"
set "WORK_DIR=%USERPROFILE%\.openclaw-docker"
set "OPENCLAW_CONFIG=%USERPROFILE%\.openclaw\openclaw.json"
set "PROXY_SCRIPT=%USERPROFILE%\agentrouter-proxy.py"

:: ── Banner ───────────────────────────────────────────────────
echo.
echo %CYAN%%BOLD%
echo   +===============================================+
echo   ^|     OpenClaw + AgentRouter Setup Script      ^|
echo   ^|     Powered by Thomas William                ^|
echo   +===============================================+
echo %NC%

:: ── Installation mode selection ──────────────────────────────
echo %BOLD%-- Installation Mode --------------------------------------------%NC%
echo.
echo   1) System-wide  - Install Node.js, Python, OpenClaw natively
echo   2) Docker        - Run everything inside a Docker container
echo.
set /p "MODE_CHOICE=%YELLOW%[?]%NC% Choose installation mode [1/2]: "

if "%MODE_CHOICE%"=="1" (
    set "INSTALL_MODE=system"
    goto :collect_inputs
)
if "%MODE_CHOICE%"=="2" (
    set "INSTALL_MODE=docker"
    goto :collect_inputs
)
echo %RED%[X]%NC% Invalid choice. Please enter 1 or 2.
pause
exit /b 1

:: ── Collect inputs ───────────────────────────────────────────
:collect_inputs
echo.
echo %BOLD%-- Configuration ------------------------------------------------%NC%
echo.

echo %YELLOW%[?]%NC% Enter your AgentRouter API key (from https://agentrouter.org/console/token):
set /p "AGENT_API_KEY="
if "!AGENT_API_KEY!"=="" (
    echo %RED%[X]%NC% API key cannot be empty.
    pause
    exit /b 1
)
echo %GREEN%[OK]%NC% API key received.
echo.

echo %CYAN%Available models on AgentRouter:%NC%
echo   1) deepseek-v3.2
echo   2) deepseek-v3.1
echo   3) deepseek-r1-0528
echo   4) glm-4.5
echo   5) glm-4.6
echo   6) claude-haiku-4-5-20251001
echo   7) claude-opus-4-6
echo   8) Enter custom model ID
echo.
set /p "MODEL_CHOICE=%YELLOW%[?]%NC% Enter the number or type your exact model ID: "

if "!MODEL_CHOICE!"=="1" set "MODEL_ID=deepseek-v3.2"
if "!MODEL_CHOICE!"=="2" set "MODEL_ID=deepseek-v3.1"
if "!MODEL_CHOICE!"=="3" set "MODEL_ID=deepseek-r1-0528"
if "!MODEL_CHOICE!"=="4" set "MODEL_ID=glm-4.5"
if "!MODEL_CHOICE!"=="5" set "MODEL_ID=glm-4.6"
if "!MODEL_CHOICE!"=="6" set "MODEL_ID=claude-haiku-4-5-20251001"
if "!MODEL_CHOICE!"=="7" set "MODEL_ID=claude-opus-4-6"
if "!MODEL_CHOICE!"=="8" (
    set /p "MODEL_ID=%YELLOW%[?]%NC% Enter your custom model ID: "
)
if not defined MODEL_ID (
    :: User typed a raw model ID
    set "MODEL_ID=!MODEL_CHOICE!"
)
if "!MODEL_ID!"=="" (
    echo %RED%[X]%NC% Model ID cannot be empty.
    pause
    exit /b 1
)
echo %GREEN%[OK]%NC% Model set to: !MODEL_ID!
echo.

set /p "CTX_INPUT=%YELLOW%[?]%NC% Enter context window size (Enter for default 128000): "
if "!CTX_INPUT!"=="" set "CTX_INPUT=128000"
set "CONTEXT_WINDOW=!CTX_INPUT!"
echo %GREEN%[OK]%NC% Context window: !CONTEXT_WINDOW! tokens
echo.

if "!INSTALL_MODE!"=="system" goto :system_install
if "!INSTALL_MODE!"=="docker" goto :docker_install

:: ════════════════════════════════════════════════════════════
::  SYSTEM-WIDE INSTALLATION
:: ════════════════════════════════════════════════════════════
:system_install
echo %BOLD%-- Checking Chocolatey -----------------------------------------%NC%
echo.
where choco >nul 2>&1
if %errorlevel% neq 0 (
    echo %CYAN%[INFO]%NC% Installing Chocolatey package manager...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    call refreshenv 2>nul
    echo %GREEN%[OK]%NC% Chocolatey installed.
) else (
    echo %GREEN%[OK]%NC% Chocolatey is already installed.
)
echo.

:: ── Node.js ─────────────────────────────────────────────────
echo %BOLD%-- Checking Node.js ---------------------------------------------%NC%
echo.
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo %CYAN%[INFO]%NC% Node.js not found. Installing Node.js 22 via Chocolatey...
    choco install nodejs --version=22.0.0 -y >nul 2>&1
    call refreshenv 2>nul
    echo %GREEN%[OK]%NC% Node.js installed.
) else (
    for /f "tokens=1 delims=." %%v in ('node -v') do (
        set "NODE_MAJOR=%%v"
        set "NODE_MAJOR=!NODE_MAJOR:v=!"
    )
    if !NODE_MAJOR! GEQ 22 (
        echo %GREEN%[OK]%NC% Node.js is installed and meets requirements ^(^>=22^).
    ) else (
        echo %YELLOW%[!]%NC% Node.js is too old. Upgrading to v22...
        choco upgrade nodejs --version=22.0.0 -y >nul 2>&1
        call refreshenv 2>nul
        echo %GREEN%[OK]%NC% Node.js upgraded.
    )
)
echo.

:: ── OpenClaw ────────────────────────────────────────────────
echo %BOLD%-- Checking OpenClaw --------------------------------------------%NC%
echo.
where openclaw >nul 2>&1
if %errorlevel% neq 0 (
    echo %CYAN%[INFO]%NC% Installing OpenClaw...
    npm install -g openclaw@latest
    echo %GREEN%[OK]%NC% OpenClaw installed.
) else (
    echo %GREEN%[OK]%NC% OpenClaw is already installed.
)
echo.

:: ── Python ──────────────────────────────────────────────────
echo %BOLD%-- Checking Python ----------------------------------------------%NC%
echo.
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo %CYAN%[INFO]%NC% Python not found. Installing via Chocolatey...
    choco install python -y >nul 2>&1
    call refreshenv 2>nul
    echo %GREEN%[OK]%NC% Python installed.
) else (
    echo %GREEN%[OK]%NC% Python is already installed.
)
echo.

echo %CYAN%[INFO]%NC% Installing required Python packages...
python -m pip install tls-client flask typing_extensions -q
echo %GREEN%[OK]%NC% Python packages installed: tls-client, flask, typing_extensions
echo.

:: ── Create proxy script ──────────────────────────────────────
echo %BOLD%-- Creating TLS proxy -------------------------------------------%NC%
echo.

(
echo import tls_client
echo from flask import Flask, request, Response
echo.
echo app = Flask(__name__)
echo.
echo @app.route('/^<path:path^>', methods=['GET', 'POST', 'OPTIONS', 'PUT'])
echo def proxy(path):
echo     session = tls_client.Session(
echo         client_identifier="chrome_120",
echo         random_tls_extension_order=False
echo     )
echo     headers = {
echo         "Content-Type": "application/json",
echo         "Authorization": request.headers.get("Authorization", ""),
echo         "User-Agent": "Kilo-Code/5.10.0",
echo         "Referer": "https://kilocode.ai",
echo         "http-referer": "https://kilocode.ai",
echo         "x-title": "Kilo Code",
echo         "x-kilocode-version": "5.10.0",
echo         "Accept": "application/json, text/plain, */*",
echo         "Accept-Language": "*",
echo         "sec-fetch-mode": "cors",
echo         "x-stainless-lang": "js",
echo         "x-stainless-package-version": "5.12.2",
echo         "x-stainless-os": "Windows",
echo         "x-stainless-arch": "x64",
echo         "x-stainless-runtime": "node",
echo         "x-stainless-runtime-version": "v22.21.1",
echo         "x-stainless-retry-count": "0",
echo     }
echo     if not path.startswith("v1/"):
echo         path = "v1/" + path
echo     url = f"https://agentrouter.org/{path}"
echo     print(f"Proxying: {request.method} {url}", flush=True)
echo     if request.method == 'POST':
echo         resp = session.post(url, headers=headers, data=request.get_data())
echo     else:
echo         resp = session.get(url, headers=headers)
echo     print(f"Response status: {resp.status_code}", flush=True)
echo     content_type = resp.headers.get("content-type", "application/json")
echo     return Response(resp.content, status=resp.status_code, content_type=content_type)
echo.
echo if __name__ == '__main__':
echo     print("AgentRouter TLS Proxy running on http://127.0.0.1:19999", flush=True)
echo     app.run(host='127.0.0.1', port=19999)
) > "!PROXY_SCRIPT!"

echo %GREEN%[OK]%NC% Proxy script created at !PROXY_SCRIPT!
echo.

:: ── Setup Windows Service via NSSM ──────────────────────────
echo %BOLD%-- Setting up Windows service -----------------------------------%NC%
echo.

where nssm >nul 2>&1
if %errorlevel% neq 0 (
    echo %CYAN%[INFO]%NC% Installing NSSM (service manager)...
    choco install nssm -y >nul 2>&1
    call refreshenv 2>nul
)

:: Stop existing service if running
nssm stop agentrouter-proxy >nul 2>&1
nssm remove agentrouter-proxy confirm >nul 2>&1

for /f "tokens=*" %%p in ('where python') do set "PYTHON_BIN=%%p"

nssm install agentrouter-proxy "!PYTHON_BIN!" "!PROXY_SCRIPT!"
nssm set agentrouter-proxy DisplayName "AgentRouter TLS Proxy for OpenClaw"
nssm set agentrouter-proxy Description "Local TLS proxy to bypass client fingerprinting for AgentRouter"
nssm set agentrouter-proxy Start SERVICE_AUTO_START
nssm set agentrouter-proxy AppStdout "%TEMP%\agentrouter-proxy.log"
nssm set agentrouter-proxy AppStderr "%TEMP%\agentrouter-proxy.err"
nssm start agentrouter-proxy

timeout /t 3 /nobreak >nul

sc query agentrouter-proxy | find "RUNNING" >nul
if %errorlevel%==0 (
    echo %GREEN%[OK]%NC% agentrouter-proxy Windows service is running and set to auto-start.
) else (
    echo %YELLOW%[!]%NC% Service may not have started. Check: %TEMP%\agentrouter-proxy.err
)
echo.

:: ── Write OpenClaw config ────────────────────────────────────
echo %BOLD%-- Writing OpenClaw config --------------------------------------%NC%
echo.

if not exist "%USERPROFILE%\.openclaw" mkdir "%USERPROFILE%\.openclaw"

:: Generate a pseudo-random token using PowerShell
for /f %%t in ('powershell -NoProfile -Command "[System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))"') do set "GW_TOKEN=%%t"

(
echo {
echo   "meta": {
echo     "lastTouchedVersion": "2026.3.7"
echo   },
echo   "models": {
echo     "mode": "merge",
echo     "providers": {
echo       "custom-agentrouter-org": {
echo         "baseUrl": "http://127.0.0.1:!PROXY_PORT!",
echo         "apiKey": "!AGENT_API_KEY!",
echo         "api": "openai-completions",
echo         "models": [
echo           {
echo             "id": "!MODEL_ID!",
echo             "name": "!MODEL_ID! (AgentRouter)",
echo             "reasoning": false,
echo             "input": ["text"],
echo             "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
echo             "contextWindow": !CONTEXT_WINDOW!,
echo             "maxTokens": 8192
echo           }
echo         ]
echo       }
echo     }
echo   },
echo   "agents": {
echo     "defaults": {
echo       "model": {
echo         "primary": "custom-agentrouter-org/!MODEL_ID!"
echo       },
echo       "compaction": { "mode": "safeguard" },
echo       "maxConcurrent": 4,
echo       "subagents": { "maxConcurrent": 8 }
echo     }
echo   },
echo   "gateway": {
echo     "mode": "local",
echo     "auth": {
echo       "mode": "token",
echo       "token": "!GW_TOKEN!"
echo     }
echo   }
echo }
) > "!OPENCLAW_CONFIG!"

echo %GREEN%[OK]%NC% OpenClaw config written to !OPENCLAW_CONFIG!
echo.

:: ── Test proxy ──────────────────────────────────────────────
echo %BOLD%-- Testing proxy connection -------------------------------------%NC%
echo.
echo %CYAN%[INFO]%NC% Sending test request via proxy...
for /f %%c in ('powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:!PROXY_PORT!/v1/chat/completions' -Method POST -Headers @{'Authorization'='Bearer !AGENT_API_KEY!'; 'Content-Type'='application/json'} -Body '{\"model\":\"!MODEL_ID!\",\"messages\":[{\"role\":\"user\",\"content\":\"say hi\"}],\"max_tokens\":10}' -UseBasicParsing; $r.StatusCode } catch { $_.Exception.Response.StatusCode.Value__ }"') do set "TEST_CODE=%%c"

if "!TEST_CODE!"=="200" (
    echo %GREEN%[OK]%NC% Proxy test passed! AgentRouter responded with HTTP 200.
) else (
    echo %YELLOW%[!]%NC% Proxy returned HTTP !TEST_CODE!. Check: %TEMP%\agentrouter-proxy.err
)
echo.

:: ── Start OpenClaw gateway ───────────────────────────────────
echo %BOLD%-- Starting OpenClaw gateway ------------------------------------%NC%
echo.
openclaw gateway install >nul 2>&1
start "OpenClaw Gateway" /min cmd /c "openclaw gateway > %TEMP%\openclaw-gateway.log 2>&1"
timeout /t 3 /nobreak >nul
tasklist | find "openclaw" >nul 2>&1
if %errorlevel%==0 (
    echo %GREEN%[OK]%NC% OpenClaw gateway started.
) else (
    echo %YELLOW%[!]%NC% Could not auto-start gateway. Run manually: openclaw gateway
)
echo.
goto :print_summary_system

:: ════════════════════════════════════════════════════════════
::  DOCKER INSTALLATION
:: ════════════════════════════════════════════════════════════
:docker_install
echo %BOLD%-- Checking Docker ----------------------------------------------%NC%
echo.

where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo %YELLOW%[!]%NC% Docker not found. Attempting to install Docker Desktop...
    where choco >nul 2>&1
    if %errorlevel% neq 0 (
        echo %CYAN%[INFO]%NC% Installing Chocolatey first...
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            "Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
        call refreshenv 2>nul
    )
    choco install docker-desktop -y
    echo %YELLOW%[!]%NC% Docker Desktop installed. Please start Docker Desktop and re-run this script.
    echo %CYAN%[INFO]%NC% Docker Desktop requires a restart or manual start before first use.
    pause
    exit /b 0
)

docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo %YELLOW%[!]%NC% Docker is installed but not running.
    echo %CYAN%[INFO]%NC% Attempting to start Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    echo %CYAN%[INFO]%NC% Waiting 20 seconds for Docker to start...
    timeout /t 20 /nobreak >nul
    docker info >nul 2>&1
    if %errorlevel% neq 0 (
        echo %RED%[X]%NC% Docker daemon is still not running. Please start Docker Desktop manually and re-run this script.
        pause
        exit /b 1
    )
)

echo %GREEN%[OK]%NC% Docker is running.
for /f "tokens=*" %%v in ('docker --version') do echo %GREEN%[OK]%NC% %%v
echo.

:: ── Create work dir ──────────────────────────────────────────
if not exist "!WORK_DIR!" mkdir "!WORK_DIR!"

echo %BOLD%-- Creating Docker setup files ----------------------------------%NC%
echo.

:: Write proxy script
(
echo import tls_client
echo from flask import Flask, request, Response
echo.
echo app = Flask(__name__)
echo.
echo @app.route('/^<path:path^>', methods=['GET', 'POST', 'OPTIONS', 'PUT'])
echo def proxy(path):
echo     session = tls_client.Session(
echo         client_identifier="chrome_120",
echo         random_tls_extension_order=False
echo     )
echo     headers = {
echo         "Content-Type": "application/json",
echo         "Authorization": request.headers.get("Authorization", ""),
echo         "User-Agent": "Kilo-Code/5.10.0",
echo         "Referer": "https://kilocode.ai",
echo         "http-referer": "https://kilocode.ai",
echo         "x-title": "Kilo Code",
echo         "x-kilocode-version": "5.10.0",
echo         "Accept": "application/json, text/plain, */*",
echo         "Accept-Language": "*",
echo         "sec-fetch-mode": "cors",
echo         "x-stainless-lang": "js",
echo         "x-stainless-package-version": "5.12.2",
echo         "x-stainless-os": "Linux",
echo         "x-stainless-arch": "x64",
echo         "x-stainless-runtime": "node",
echo         "x-stainless-runtime-version": "v22.21.1",
echo         "x-stainless-retry-count": "0",
echo     }
echo     if not path.startswith("v1/"):
echo         path = "v1/" + path
echo     url = f"https://agentrouter.org/{path}"
echo     print(f"Proxying: {request.method} {url}", flush=True)
echo     if request.method == 'POST':
echo         resp = session.post(url, headers=headers, data=request.get_data())
echo     else:
echo         resp = session.get(url, headers=headers)
echo     print(f"Response status: {resp.status_code}", flush=True)
echo     content_type = resp.headers.get("content-type", "application/json")
echo     return Response(resp.content, status=resp.status_code, content_type=content_type)
echo.
echo if __name__ == '__main__':
echo     print("AgentRouter TLS Proxy running on http://0.0.0.0:19999", flush=True)
echo     app.run(host='0.0.0.0', port=19999)
) > "!WORK_DIR!\agentrouter-proxy.py"

:: Generate token
for /f %%t in ('powershell -NoProfile -Command "[System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))"') do set "GW_TOKEN=%%t"

:: Write openclaw config
(
echo {
echo   "meta": {
echo     "lastTouchedVersion": "2026.3.7"
echo   },
echo   "models": {
echo     "mode": "merge",
echo     "providers": {
echo       "custom-agentrouter-org": {
echo         "baseUrl": "http://127.0.0.1:!PROXY_PORT!",
echo         "apiKey": "!AGENT_API_KEY!",
echo         "api": "openai-completions",
echo         "models": [
echo           {
echo             "id": "!MODEL_ID!",
echo             "name": "!MODEL_ID! (AgentRouter)",
echo             "reasoning": false,
echo             "input": ["text"],
echo             "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
echo             "contextWindow": !CONTEXT_WINDOW!,
echo             "maxTokens": 8192
echo           }
echo         ]
echo       }
echo     }
echo   },
echo   "agents": {
echo     "defaults": {
echo       "model": {
echo         "primary": "custom-agentrouter-org/!MODEL_ID!"
echo       },
echo       "compaction": { "mode": "safeguard" },
echo       "maxConcurrent": 4,
echo       "subagents": { "maxConcurrent": 8 }
echo     }
echo   },
echo   "gateway": {
echo     "mode": "local",
echo     "auth": {
echo       "mode": "token",
echo       "token": "!GW_TOKEN!"
echo     }
echo   }
echo }
) > "!WORK_DIR!\openclaw.json"

:: Write Dockerfile
(
echo FROM ubuntu:24.04
echo ENV DEBIAN_FRONTEND=noninteractive
echo RUN apt-get update ^&^& apt-get install -y \
echo     curl ca-certificates python3 python3-pip openssl \
echo     ^&^& rm -rf /var/lib/apt/lists/*
echo RUN curl -fsSL https://deb.nodesource.com/setup_22.x ^| bash - \
echo     ^&^& apt-get install -y nodejs
echo RUN pip install tls-client flask typing_extensions --break-system-packages -q
echo RUN npm install -g openclaw@latest
echo COPY agentrouter-proxy.py /app/agentrouter-proxy.py
echo COPY openclaw.json /root/.openclaw/openclaw.json
echo COPY entrypoint.sh /app/entrypoint.sh
echo RUN chmod +x /app/entrypoint.sh
echo WORKDIR /app
echo EXPOSE 19999
echo ENTRYPOINT ["/app/entrypoint.sh"]
) > "!WORK_DIR!\Dockerfile"

:: Write entrypoint.sh (Linux line endings handled by Docker build)
(
echo #!/bin/bash
echo set -e
echo echo "[Entrypoint] Starting AgentRouter TLS Proxy..."
echo python3 /app/agentrouter-proxy.py ^&
echo PROXY_PID=$!
echo sleep 2
echo echo "[Entrypoint] Starting OpenClaw gateway..."
echo openclaw gateway install 2^>/dev/null ^|^| true
echo openclaw gateway ^&
echo GW_PID=$!
echo echo "[Entrypoint] All services started."
echo wait -n $PROXY_PID $GW_PID
) > "!WORK_DIR!\entrypoint.sh"

:: Convert entrypoint.sh to Unix line endings using PowerShell
powershell -NoProfile -Command ^
    "(Get-Content '!WORK_DIR!\entrypoint.sh') -join \"`n\" | Set-Content -NoNewline '!WORK_DIR!\entrypoint.sh'"

echo %GREEN%[OK]%NC% Docker setup files created in !WORK_DIR!
echo.

:: ── Build Docker image ───────────────────────────────────────
echo %BOLD%-- Building Docker image ----------------------------------------%NC%
echo.
echo %CYAN%[INFO]%NC% Building openclaw-agentrouter image (this may take a few minutes)...
docker build -t openclaw-agentrouter "!WORK_DIR!"
if %errorlevel% neq 0 (
    echo %RED%[X]%NC% Docker build failed. Check the output above.
    pause
    exit /b 1
)
echo %GREEN%[OK]%NC% Docker image built: openclaw-agentrouter
echo.

:: ── Run container ────────────────────────────────────────────
echo %BOLD%-- Starting Docker container ------------------------------------%NC%
echo.
docker rm -f openclaw-agentrouter >nul 2>&1
docker run -d --name openclaw-agentrouter --restart unless-stopped -p !PROXY_PORT!:!PROXY_PORT! openclaw-agentrouter
timeout /t 4 /nobreak >nul

docker ps --filter "name=openclaw-agentrouter" --filter "status=running" | find "openclaw" >nul
if %errorlevel%==0 (
    echo %GREEN%[OK]%NC% Container openclaw-agentrouter is running.
) else (
    echo %YELLOW%[!]%NC% Container may not be running. Check: docker logs openclaw-agentrouter
)
echo.

:: ── Test proxy ──────────────────────────────────────────────
echo %BOLD%-- Testing proxy connection -------------------------------------%NC%
echo.
echo %CYAN%[INFO]%NC% Sending test request via proxy...
for /f %%c in ('powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:!PROXY_PORT!/v1/chat/completions' -Method POST -Headers @{'Authorization'='Bearer !AGENT_API_KEY!'; 'Content-Type'='application/json'} -Body '{\"model\":\"!MODEL_ID!\",\"messages\":[{\"role\":\"user\",\"content\":\"say hi\"}],\"max_tokens\":10}' -UseBasicParsing; $r.StatusCode } catch { $_.Exception.Response.StatusCode.Value__ }"') do set "TEST_CODE=%%c"
if "!TEST_CODE!"=="200" (
    echo %GREEN%[OK]%NC% Proxy test passed! AgentRouter responded with HTTP 200.
) else (
    echo %YELLOW%[!]%NC% Proxy returned HTTP !TEST_CODE!. Check: docker logs openclaw-agentrouter
)
echo.
goto :print_summary_docker

:: ── Summaries ────────────────────────────────────────────────
:print_summary_system
echo %GREEN%%BOLD%
echo   +===============================================+
echo   ^|           Setup Complete!  (^_^)              ^|
echo   +===============================================+
echo %NC%
echo   Mode:     System-wide
echo   Model:    !MODEL_ID!
echo   Proxy:    http://127.0.0.1:!PROXY_PORT!
echo   Config:   !OPENCLAW_CONFIG!
echo.
echo   Open chat TUI:       openclaw tui
echo   Check gateway:       openclaw health
echo   Check proxy service: sc query agentrouter-proxy
echo   Proxy logs:          %TEMP%\agentrouter-proxy.log
echo.
pause
exit /b 0

:print_summary_docker
echo %GREEN%%BOLD%
echo   +===============================================+
echo   ^|           Setup Complete!  (^_^)              ^|
echo   +===============================================+
echo %NC%
echo   Mode:     Docker
echo   Model:    !MODEL_ID!
echo   Proxy:    http://127.0.0.1:!PROXY_PORT!
echo   Config:   !WORK_DIR!\openclaw.json
echo.
echo   Container logs:  docker logs -f openclaw-agentrouter
echo   Stop container:  docker stop openclaw-agentrouter
echo   Restart:         docker restart openclaw-agentrouter
echo.
pause
exit /b 0
