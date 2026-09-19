---
name: session-start-hook-output
description: How SessionStart hook output reaches the user vs Claude, and why check-gh-auth.sh emits JSON
metadata:
  type: project
---

For `SessionStart` command hooks: plain-text stdout is added to Claude's
context (Claude sees it, the user generally does not). To show the user a line,
emit JSON with `systemMessage`. To also give Claude context, add
`hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: "..."}`.
Exit 0 always; exit 2 would block session start. Matcher values are `startup`,
`resume`, `clear`, `compact`, `fork`. `mcp_tool` hooks are unavailable at
SessionStart because MCP servers are not up yet. Confirmed 2026-09-19 from the
hooks reference.

**Why:** design decision 5 says the hook nudges the person and never blocks; a
plain `echo` would only nudge Claude.

**How to apply:** `scripts/check-gh-auth.sh` prints nothing when both logins
exist, otherwise one JSON object with both fields, and the matcher is
`startup|resume|clear` so a `compact` mid-session does not re-nudge. Uses
`gh auth token --hostname X` (keyring only, no network) rather than
`gh auth status` (network call) to stay fast and offline-safe.
