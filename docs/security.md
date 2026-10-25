# Security model

**High impact:** WolframLanguageEvaluator can execute arbitrary Wolfram Language with access to the user's files and environment. Treat the MCP endpoint like a remote shell.

This reference deliberately does not enable `mcp-proxy --apiKey`. The earlier test found interoperability complications involving HTTP authentication challenges and the tunnel client's OAuth discovery. **No OAuth does not mean no access control.** In the reference setup, access is limited by network firewall rules and the OpenAI tunnel's authenticated control plane.

Required controls:

1. Windows inbound firewall default-deny policy must be enabled, including on current profiles.
2. Explicitly allow only the trusted Linux host and target Windows address/port, scoped to the dedicated `node-wolfram.exe` path.
3. Audit other allow rules for the same executable or port; Windows filter precedence and other security software can alter effective restrictions.
4. Never enable public forwarding, tunnel exposure of raw MCP HTTP, or access from guest Wi-Fi.
5. Protect OpenAI runtime API key at rest; prefer OS-managed secret storage when adapting the installer for general deployment.
6. Treat the supervisor logs and task credentials as sensitive, and do not commit them.
7. Use a dedicated least-privilege Windows account if possible; the sample scheduled task uses the invoking user and should be reviewed in your environment.
8. Reevaluate after dependency upgrades. The proxy and tunnel are pinned to tested versions deliberately.

If any untrusted hosts share the LAN, **do not deploy this direct-listener reference as-is**. Adapt it to a loopback listener with private point-to-point forwarding or add a vetted authentication layer and retest the non-OAuth tunnel compatibility.
