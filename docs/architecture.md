# Architecture and boundaries

The single MCP-backed `wolfram.exe` is launched by Wolfram AgentTools as the stdio child of a pinned `mcp-proxy` process. `mcp-proxy` accepts multiple Streamable HTTP sessions and multiplexes them onto one upstream session. OpenAI's Secure MCP Tunnel calls that same HTTP endpoint from the Windows machine, while trusted LAN clients call the endpoint directly.

The Windows `pythonw.exe` supervisor owns both the proxy and tunnel process. It creates a Windows Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so closing the supervisor also terminates its managed descendants. If either child exits, it closes the job and restarts both. The scheduled task is the sole startup owner.

## Trade-offs

- One kernel means one shared global Wolfram state. Do not expect session isolation between ChatGPT, Claude, and Codex.
- A client may connect independently; connection count does not determine Wolfram process count.
- Concurrent evaluations that mutate state require discipline. The reference deployment does not enforce an application-level single-flight queue; do not assume strict FIFO ordering.
- `mcp-proxy` may not propagate MCP roots, sampling, or elicitation. Confirm if new Wolfram AgentTools workflows rely on them.
- A separately launched Mathematica Desktop kernel may consume an additional controlling-process license.
- Exact Windows startup behavior can depend on the scheduled task logon account, access to the user credential, environment variables, and network readiness.
- System security depends on Windows Firewall and network topology, **not** on MCP authentication headers.

## Tested environment, non-normative

Windows 11, Wolfram 15.0.1, AgentTools 2.2.0, Node.js, `mcp-proxy` 6.7.21, OpenAI tunnel-client-runtime 0.0.18, DGX Spark Ubuntu Codex CLI / Claude Code. Live tests demonstrated identical Wolfram `$ProcessID` across all three clients, including after a Windows reboot, with Mathematica Desktop also evaluating separately.
