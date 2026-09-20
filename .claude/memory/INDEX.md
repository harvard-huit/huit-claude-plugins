# Project memory index

Portable, project-scoped facts. Imported by CLAUDE.md. One line per memory.

- [GHES OAuth needs own app](ghes-oauth-needs-own-app.md) — github-mcp-server's built-in OAuth is github.com only; GHES would need an app registered on the instance, so the wrapper uses `gh`'s token
- [SessionStart hook output](session-start-hook-output.md) — plain stdout goes to Claude only; `systemMessage` JSON reaches the user; use `gh auth token` not `gh auth status` for a no-network check
- [Redact token scripts when testing](redact-token-scripts-when-testing.md) — always pipe `gh auth token` / the headers helper through sed or `cut -c1-4`; empty `GH_CONFIG_DIR` is not a no-login test (leaked a PAT 2026-09-20)
