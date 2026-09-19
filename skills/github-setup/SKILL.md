---
name: github-setup
description: Set up GitHub access for AAIS / HUIT in Claude Code without a Personal Access Token. Installs gh and the GitHub MCP server binary, runs gh device-flow login for github.com and/or github.huit.harvard.edu, connects the github MCP server via /mcp OAuth, and optionally adds a narrow read-only gh allowlist. Use when the user asks to set up, connect, log in to, or fix GitHub access, or when a github MCP server shows as disconnected or gh reports no login.
---

# GitHub setup (HUIT)

You are walking one person through connecting Claude Code to GitHub. The goal is
**zero Personal Access Tokens**. Every credential comes from an OAuth login the
person completes in their browser. You cannot install or log in on their behalf:
propose each command, explain what it does in one line, and let them approve it.

Two GitHubs are in play. Ask which the person needs before installing anything.

| Host | Org | How Claude reaches it | Auth |
|---|---|---|---|
| github.com | `harvard-huit` (SAML SSO) | remote GitHub MCP server (`github`) | OAuth via `/mcp` |
| github.huit.harvard.edu (GHES) | `HUIT` | local `github-mcp-server` behind `bin/github-mcp-ghes.sh` (`github-huit`) | `gh auth login` device flow |

`gh` is the fallback for both hosts when MCP tools are unavailable.

## 1. Inventory first

Run these read-only checks and summarize the result in a few lines. Do not skip
steps the person already completed.

```sh
command -v gh && gh --version | head -1
command -v github-mcp-server && github-mcp-server --version
gh auth token --hostname github.com >/dev/null 2>&1 && echo "github.com: logged in" || echo "github.com: no login"
gh auth token --hostname github.huit.harvard.edu >/dev/null 2>&1 && echo "GHES: logged in" || echo "GHES: no login"
uname -s
```

Also check whether the `github` and `github-huit` MCP servers are currently
connected (their tools appear in your tool list, or `/mcp` lists them). If the
tools are present, the corresponding OAuth step is already done.

Then ask: **github.com, GHES, or both?** Only do the steps for what they need.

## 2. Install `gh` (both hosts)

Skip if present.

- macOS: `brew install gh`
- Debian/Ubuntu: follow https://github.com/cli/cli/blob/trunk/docs/install_linux.md (apt repo), or `sudo apt install gh` if their distro already ships it
- Fedora/RHEL: `sudo dnf install gh`
- Anything else: https://cli.github.com

## 3. Install `github-mcp-server` (GHES only)

Skip unless they need GHES. The remote github.com server needs no binary.

- macOS or Linuxbrew: `brew install github-mcp-server`
- Other Linux: download the latest release tarball for their arch from
  https://github.com/github/github-mcp-server/releases and put the
  `github-mcp-server` binary somewhere on PATH (for example `~/.local/bin`).
  Docker is also supported by the upstream project, but the wrapper script in
  this plugin expects a binary on PATH.

## 4. Log in with `gh` (device flow, no PAT)

One login per host they need. `--web` opens the browser device-code flow; `gh`
stores the resulting OAuth token in the OS keyring.

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth login --hostname github.huit.harvard.edu --git-protocol https --web
```

Notes to relay when relevant:

- The person picks "HTTPS" and "Login with a web browser" if prompted. Say yes to
  "Authenticate Git with your GitHub credentials" so `git push` also stops
  needing a PAT.
- **github.com + SAML:** `harvard-huit` enforces SAML SSO. If `gh api user/orgs`
  or a repo call later returns 403 mentioning SAML, the person must authorize the
  token for the org: `gh auth refresh --hostname github.com` and follow the
  SSO prompt, or visit the org's SSO page in their browser.
- **GHES:** the classic-PAT `Authorization: Bearer` 401 gotcha does not apply to
  OAuth tokens from `gh`, but GHES support is still being confirmed. If
  `gh auth login` against GHES fails, capture the exact error and stop; do not
  fall back to creating a PAT.

Verify each login without network calls: `gh auth token --hostname <host> >/dev/null && echo ok`.
For a real round-trip: `gh api --hostname <host> user --jq .login`.

## 5. Connect the MCP servers

**github.com (remote, OAuth):** tell the person to run `/mcp`, select
`github`, and complete the browser login. That authorization is against GitHub
directly, not Anthropic. If it fails with an org-authorization or SAML message,
an owner of `harvard-huit` must approve the GitHub MCP OAuth app for the org
once. That is the single admin ask on this path; name it plainly rather than
working around it.

**GHES (local binary):** nothing to authorize beyond step 4. After the `gh`
login, `/mcp` should show `github-huit` as connected (the wrapper reads the
token from `gh`). If it shows failed, run the wrapper by hand to see its
stderr, then fix what it reports. Get the install path from
`claude plugin list --json` (the `installPath` field; typically
`~/.claude/plugins/cache/huit-claude-plugins/huit-github/<version>`), then:

```sh
"<installPath>"/bin/github-mcp-ghes.sh </dev/null
```

Common causes: binary not on PATH, no `gh` login for the GHES host. MCP servers
may launch with a minimal PATH; the wrapper adds Homebrew and `~/.local/bin`.

## 6. Optional: narrow read-only `gh` allowlist

Plugins cannot ship permissions, so offer (do not assume) to add a small
allowlist to the person's `~/.claude/settings.json` so read-only `gh` calls stop
prompting. Show exactly what you will add and wait for a yes. Merge into the
existing `permissions.allow` array; never overwrite other entries.

```json
"Bash(gh auth status:*)",
"Bash(gh repo view:*)",
"Bash(gh pr list:*)",
"Bash(gh pr view:*)",
"Bash(gh pr diff:*)",
"Bash(gh pr checks:*)",
"Bash(gh issue list:*)",
"Bash(gh issue view:*)",
"Bash(gh run list:*)",
"Bash(gh run view:*)",
"Bash(gh search:*)"
```

Rules: **never** add bare `Bash(gh:*)` or `Bash(gh *)`. Do not add `gh api`
even though it is often read-only; it also performs writes with `-X`/`--method`
and cannot be constrained by a prefix rule. Writes (`gh pr create`, `gh pr
merge`, `gh issue create`, `gh repo delete`, ...) must keep prompting.

## 7. Verify and hand off

Do one real read per host they set up, preferring MCP tools and falling back to
`gh`: for example, list open PRs on a repo they name, or `gh repo view <org>/<repo>`.
Then tell them, in a few lines, what is connected, what is not, and what still
needs an admin (the SAML OAuth-app approval, if it came up).

## Ongoing usage guidance

- Prefer the `github` / `github-huit` MCP tools when connected; fall back to
  `gh --hostname <host>` when they are not. Say which you are using if it matters.
- Some repos are live on GHES while the github.com copy is a stale mirror.
  Compare `pushed_at` on both before assuming which is canonical.
- Cross-instance `#N` references do not auto-link. Use full URLs when citing
  issues or PRs across the two hosts.
- `gh` on GHES: if a call returns 401 with a classic PAT in play, that is the
  known `Authorization: Bearer` rejection; the fix is to use the `gh` OAuth login,
  not another PAT.
