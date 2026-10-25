# Wolfram MCP Shared Kernel

[![Platform](https://img.shields.io/badge/platform-Windows%2011-0078D4?logo=windows11&logoColor=white)](https://learn.microsoft.com/en-us/windows/)
[![MCP](https://img.shields.io/badge/protocol-MCP%20Streamable%20HTTP-0A7E8C)](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
[![Wolfram](https://img.shields.io/badge/Wolfram-AgentTools-DD1100)](https://github.com/WolframResearch/AgentTools)
[![mcp-proxy](https://img.shields.io/badge/mcp--proxy-6.7.21-blue)](https://github.com/punkpeye/mcp-proxy)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-reference%20implementation-orange)](#project-status)

**Use a single Windows-hosted Wolfram Language kernel from ChatGPT, Codex CLI, and Claude Code through one shared MCP endpoint.** In the original verified installation, the Wolfram license reported **\`$MaxLicenseProcesses = 2\`**: one licensed controlling process was used for the shared MCP backend and the other for Mathematica Desktop. This entitlement is **license-specific**, not guaranteed for other installations.

This project combines Wolfram's official AgentTools server, the open-source `mcp-proxy` multiplexer, and OpenAI's official Secure MCP Tunnel. **No OAuth server, no duplicate Wolfram kernels per client, and no public router port forwarding.**

## How it works

```text
          ChatGPT (cloud)                  Codex CLI + Claude Code (trusted Linux)
                |                                           |
     OpenAI Secure MCP Tunnel                     Private LAN connection
       outbound HTTPS only                                  |
                |                                           |
                +-------------------+-----------------------+
                                    |
                         mcp-proxy Streamable HTTP
                                    |
                          one upstream stdio session
                                    |
                         Wolfram AgentTools server
                                    |
                            one wolfram.exe

          Mathematica Desktop ─────── separate kernel, if licensed
```

All three MCP clients share the same **Wolfram operating-system process**, as confirmed using `$ProcessID`. **That does not imply they share the same evaluator session or variable definitions.** Wolfram AgentTools' evaluator exposes session handling; different evaluator session IDs can have different contexts and histories. Session continuity depends on passing the appropriate session identifier, not merely on connecting to the same proxy. Cross-client namespace isolation was verified experimentally between ChatGPT and Claude Code (both PID `10028`, but Claude's new session returned no own-value for ChatGPT's probe symbol); restart persistence remains unverified; see [Session state](docs/architecture.md#evaluation-state-versus-process-state) and [session tests](docs/testing.md#evaluator-session-state-tests). The reference implementation does not guarantee serialized FIFO execution of overlapping mutating requests.

**Three-client isolation verified (2026-10-24):** ChatGPT evaluator session `gLZFoCfY` set `mcpIsolationProbe20261024 = 424242`; Claude Code fresh session `q6YjKGjB` and Codex fresh session `yuyKZMfK` each evaluated `{$ProcessID, OwnValues[mcpIsolationProbe20261024]}` and returned `{10028, {}}`. All three shared kernel PID `10028`, while own-values in the ChatGPT session were not visible from the other sessions. These results verify logical evaluator namespace isolation, **not** security isolation or persistence across server restarts.

## Quickstart

### 1. Prerequisites

- Windows 11 with Mathematica/Wolfram 15 and the official `Wolfram/AgentTools` paclet.
- Node.js, npm, and Python 3 including `pythonw.exe`.
- The [OpenAI Secure MCP Tunnel runtime](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), a valid tunnel ID, and an authorized runtime API key.
- An optional trusted Linux/DGX machine with Codex CLI and Claude Code, reachable from Windows via passwordless SSH.
- Administrator PowerShell for the Windows startup task and scoped firewall configuration.

Place the official `tunnel-client-runtime.exe` in `%LOCALAPPDATA%\WolframMCP\tunnel\tunnel-client-runtime.exe` (or specify `-TunnelExe`). Configure `CONTROL_PLANE_API_KEY` in the **Windows User** environment securely. Never include the key in repository files or command arguments.

### 2. Install (Administrator PowerShell)

Clone the repository, change into it, and substitute **your own** host details and tunnel ID:

```powershell
git clone https://github.com/miramar-labs/wolfram-mcp-shared-kernel.git
cd wolfram-mcp-shared-kernel

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-WolframMCP.ps1 `
  -DgxAddress '<TRUSTED_LINUX_IPV4>' `
  -MsiAddress '<WINDOWS_IPV4>' `
  -DgxSshTarget '<USER@LINUX_HOST>' `
  -TunnelId '<YOUR_OPENAI_TUNNEL_ID>'
```

The installer pins `mcp-proxy@6.7.21`, creates the headless `Wolfram MCP Unified` scheduled task, configures a restricted Windows firewall rule, and registers the `wolfram-windows` MCP server for Codex and Claude Code.

### 3. Verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-WolframMCP.ps1 -Mode Status
```

- The Windows scheduled task should be **Running**.
- The OpenAI tunnel readiness endpoint `http://127.0.0.1:18766/readyz` should return **HTTP 200**.
- Exactly **one MCP-owned** `wolfram.exe` should be a child of `node-wolfram.exe`.
- In ChatGPT, Codex, and Claude Code, call `WolframLanguageContext` followed by `WolframLanguageEvaluator` on `{$ProcessID,2+2}`. All three should return the **same process ID** and `4`.

### Optional: CUDA smoke test

On an NVIDIA-equipped Windows Wolfram host, you can verify GPU discovery and a real `CUDADot` matrix computation through any MCP client. **CUDA is not required** for the shared MCP architecture. The original installation passed on an NVIDIA GeForce RTX 4060 Laptop GPU (compute capability 8.9, NVIDIA driver 591.44), with GPU and CPU matrix results matching exactly. See [CUDA verification and reproducible test](docs/cuda.md).

### 4. Status or uninstall

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-WolframMCP.ps1 -Mode Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-WolframMCP.ps1 -Mode Uninstall
```

Uninstall removes the managed Windows task and firewall rule but intentionally preserves logs, runtime files, and Mathematica itself. DGX MCP registrations can be removed separately using `codex mcp remove wolfram-windows` and `claude mcp remove wolfram-windows -s user`.

## Security — important

> [!WARNING]
> The shared HTTP MCP endpoint has **no application-layer authentication** in this reference deployment. Wolfram evaluations can execute code with the privileges of the Windows account running the task. Do not expose TCP 8765 to the internet or untrusted LAN clients.

The reference uses Windows Firewall rules scoped to a trusted host and a dedicated proxy executable, plus an authenticated outbound OpenAI tunnel. **Review all effective firewall rules and network profiles** before deployment. A permissive unrelated rule may defeat the intended restrictions. See [Security](docs/security.md).

## Project status

**The original working deployment** was verified across ChatGPT, Codex, and Claude Code with a common `$ProcessID`, survived a Windows reboot, and ran alongside an independently evaluated Mathematica desktop notebook.

**The public, parameterized installer is a reference implementation** and has not yet been independently tested on other machines. Review and test before production use.

## Documentation

- [Architecture and limitations](docs/architecture.md)
- [Security model](docs/security.md)
- [Acceptance tests](docs/testing.md)
- [Optional CUDA verification](docs/cuda.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Official references](docs/references.md)

## Technology and licenses

- [Wolfram AgentTools](https://github.com/WolframResearch/AgentTools) — official Wolfram Language MCP server
- [mcp-proxy](https://github.com/punkpeye/mcp-proxy) — community HTTP-to-stdio multiplexer, pinned to 6.7.21
- [OpenAI Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels) — outbound cloud access, runtime 0.0.18 tested

Repository scripts and documentation are MIT licensed; third-party software retains its respective licenses and terms. No Wolfram or OpenAI binaries are distributed here.
