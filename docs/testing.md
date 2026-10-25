# Acceptance plan

Do not treat task status alone as proof of a working installation.

1. **Start:** `Get-ScheduledTask -TaskName 'Wolfram MCP Unified'`; check Task State = Running.
2. **Tree:** `Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('pythonw.exe','node-wolfram.exe','tunnel-client-runtime.exe','wolfram.exe') } | Select ProcessId,ParentProcessId,Name`. Expect one Wolfram MCP process whose parent is the dedicated Node proxy. Other Mathematica notebook kernels are possible.
3. **Tunnel:** `Invoke-WebRequest -UseBasicParsing http://127.0.0.1:18766/readyz` returns status 200.
4. **MCP handshake:** Streamable HTTP `initialize` on `http://127.0.0.1:8765/mcp` reports `WolframLanguage` server (do not send untrusted payloads).
5. **Cloud:** From ChatGPT's Wolfram MCP tools run `{$ProcessID,2+2}`. Note PID P.
6. **DGX Codex:** `codex mcp list`; in Codex call context then evaluator for `{$ProcessID,37*41}`. Expect `{P,1517}`.
7. **DGX Claude:** `claude mcp list`; call context then evaluator for `{$ProcessID,19*23}`. Expect `{P,437}`.
8. **Desktop:** Run Mathematica GUI notebook `2+2` and verify `4`; inspect license entitlement before exceeding allowed controlling processes.
9. **Restart/reboot:** Restart task and repeat step 5-7; PID should change across a true kernel restart, but agree among clients afterward. Confirm no extra MCP processes and no console windows.
10. **Negative security test:** From a non-allowlisted host attempt to connect to Windows TCP 8765; it should fail. Verify only the trusted host can connect. This test is essential for unauthenticated LAN mode.

Record date, versions, kernel PID, Windows firewall profile, and relevant startup logs. **Never record API key values.**

## Evaluator session state tests

These tests are **not yet passed** in the verified reference deployment; the cross-client `$ProcessID` test proves shared process identity only. Run them against a disposable server or with non-conflicting unique names, not production notebooks.

1. **Session A persistence:** From ChatGPT call `WolframLanguageEvaluator` with an assignment such as `mcpSessionProbeA = 424242` using its documented session API. Record any returned evaluator session ID, and in a second call explicitly reuse that ID to evaluate `mcpSessionProbeA`. Expect `424242` **only if** the evaluator method/session retains assignments.
2. **Session B isolation:** From Claude or Codex create a **new evaluator session**, avoiding A's evaluator session ID. Query `mcpSessionProbeA` with the same selected evaluator method. Record whether it is unassigned, shadowed, or visible. A process ID match does **not** determine this result.
3. **Explicit sharing:** Only when supported, deliberately use session A's identifier from another client and check whether definitions and history continue. Treat that session ID as potentially sensitive; do not log or publish live IDs.
4. **Global/process side effects:** Check whether explicitly qualified global symbols or file writes are visible across evaluator sessions. Report these separately from lexical/context isolation.
5. **Restart:** Restart the MCP-owned server; confirm a new process ID and reconnect. Attempt to resume the same evaluator session according to AgentTools documentation. Record whether definitions, evaluation history, or neither survive; do **not** infer persistence from tunnel readiness.
6. **Kernel count:** Before and after each evaluation, inspect parent-child processes. Reject any evaluator method that starts a second licensed Wolfram kernel if the single-MCP-kernel limit is required.

Record AgentTools version, evaluator method, whether a session ID was supplied, and the results. Clean up probe definitions through the supported evaluator context. Never assume that MCP `Mcp-Session-Id` equals the Wolfram evaluator session identifier.
