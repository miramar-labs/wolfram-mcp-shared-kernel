# Architecture and boundaries

The single MCP-backed `wolfram.exe` is launched by Wolfram AgentTools as the stdio child of a pinned `mcp-proxy` process. `mcp-proxy` accepts multiple Streamable HTTP sessions and multiplexes them onto one upstream session. OpenAI's Secure MCP Tunnel calls that same HTTP endpoint from the Windows machine, while trusted LAN clients call the endpoint directly.

The Windows `pythonw.exe` supervisor owns both the proxy and tunnel process. It creates a Windows Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so closing the supervisor also terminates its managed descendants. If either child exits, it closes the job and restarts both. The scheduled task is the sole startup owner.

## Evaluation state versus process state

**Three different layers must not be conflated:**

| Layer | What is shared / retained |
| --- | --- |
| Windows `wolfram.exe` | One licensed controlling process for the shared AgentTools server; confirmed by matching `$ProcessID` from ChatGPT, Claude Code, and Codex |
| MCP transport sessions | Separate downstream Streamable HTTP connections are multiplexed into the single upstream stdio connection; MCP session identity is not automatically an evaluator session ID |
| Wolfram evaluator sessions | AgentTools can use evaluator session identifiers to continue an evaluation context/history. Definitions made under one evaluator session are not automatically available under another session ID |

The same kernel can therefore serve **distinct logical evaluator sessions**. Conversely, reusing a valid evaluator session ID may continue that session's definitions even from a different MCP client, depending on AgentTools' supported session semantics and access rules.

Do not assume that an unqualified assignment such as `x = 42` in one client is visible to another client. Do not assume sessions are completely isolated either without testing their actual context behavior, especially explicit `Global\`symbol`, process-global state or side effects such as files.

AgentTools may offer different evaluation methods (including a method that evaluates through a separate local kernel). Any method that spawns another kernel is **outside the single-process requirement**. Verify the evaluator method and process count when changing defaults.

**Restart persistence is unproven in this repository.** Some evaluator session mechanisms may persist metadata or history, but whether definitions are restored after a restart depends on the documented AgentTools version, method and storage configuration. The existing reboot test verified new process startup and client reconnection—not definition persistence.

See [evaluator session tests](testing.md#evaluator-session-state-tests) before promising session isolation or persistence to users.

## Trade-offs

- One kernel means a shared **process**, not necessarily one shared evaluator namespace. Client connections and Wolfram evaluator session IDs are distinct; explicit shared/global side effects still require care.
- A client may connect independently; connection count does not determine Wolfram process count.
- Concurrent evaluations that mutate state require discipline. The reference deployment does not enforce an application-level single-flight queue; do not assume strict FIFO ordering.
- `mcp-proxy` may not propagate MCP roots, sampling, or elicitation. Confirm if new Wolfram AgentTools workflows rely on them.
- A separately launched Mathematica Desktop kernel may consume an additional controlling-process license.
- Exact Windows startup behavior can depend on the scheduled task logon account, access to the user credential, environment variables, and network readiness.
- System security depends on Windows Firewall and network topology, **not** on MCP authentication headers.

## Tested environment, non-normative

Windows 11, Wolfram 15.0.1, AgentTools 2.2.0, Node.js, `mcp-proxy` 6.7.21, OpenAI tunnel-client-runtime 0.0.18, DGX Spark Ubuntu Codex CLI / Claude Code. Live tests demonstrated identical Wolfram `$ProcessID` across all three clients, including after a Windows reboot, with Mathematica Desktop also evaluating separately.
