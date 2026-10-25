# Troubleshooting

- **No tunnel `/readyz`:** Inspect `%LOCALAPPDATA%\WolframMCP\logs\supervisor.log` and `tunnel.log`; verify `CONTROL_PLANE_API_KEY` is readable from the scheduled-task account and tunnel ID is valid.
- **Two MCP kernels:** Check both process parents and scheduled tasks. Stop duplicate old tasks/processes before restarting the authoritative one. Do not kill an unrelated desktop kernel.
- **DGX timeout:** Confirm Windows listener and firewall allow rule, DGX source IP, Windows network profile, and whether a broad Node.js Block rule shadows the expected Allow. **Never globally disable Windows Firewall** as a workaround.
- **HTTP 400 for plain `curl /mcp`:** It can mean the endpoint is reachable but request lacks a valid MCP operation; use a JSON-RPC initialize call for a real handshake.
- **Unauthorized discovery / OAuth metadata errors:** Ensure the local target is the documented no-OAuth HTTP configuration. Do not add OAuth merely to silence a diagnostic; inspect the actual discovery HTTP status and headers.
- **Codex model/sandbox errors:** Test Codex in its normal interactive mode; CLI model or sandbox errors can be unrelated to MCP.
- **Console popup:** Ensure Task Scheduler runs `pythonw.exe`, not `python.exe` or a visible PowerShell script.
- **Recovery loops:** The supervisor restarts its children when either exits. Examine logs and ensure no other service holds the ports before repeated restarts.
- **Uninstall:** `-Mode Uninstall` removes the Windows scheduled task and scoped firewall rule but intentionally leaves files and does not remove DGX client configurations. Unregister the latter with `codex mcp remove wolfram-windows` and `claude mcp remove wolfram-windows -s user` if desired.
