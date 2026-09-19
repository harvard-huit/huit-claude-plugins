# huit-github

A Claude Code plugin that connects Claude to GitHub for the AAIS group / HUIT
org **without creating or storing a Personal Access Token**. Everything
authenticates with an OAuth login you complete in your browser.

It covers both GitHubs we use:

| Host | Org | How it works |
|---|---|---|
| github.com | `harvard-huit` | GitHub's hosted MCP server, OAuth via `/mcp` |
| github.huit.harvard.edu (GHES) | `HUIT` | GitHub's `github-mcp-server` binary run locally, using the token from `gh auth login` |

## Install

This repo is internal to the `harvard-huit` enterprise on github.com, so first
make sure `gh` is logged in there (`gh auth login --hostname github.com --web`).
Then two commands inside Claude Code:

```
/plugin marketplace add harvard-huit/huit-github-plugin
/plugin install huit-github@huit-plugins
```

Then run the setup skill and follow along:

```
/huit-github:github-setup
```

It checks what you already have, installs `gh` (and `github-mcp-server` if you
need GHES), runs `gh auth login --web` for the host(s) you need, and has you run
`/mcp` once to authorize the github.com server. You approve every command.

## What you get

- MCP tools for issues, pull requests, repos, code search, Actions runs, etc. on
  whichever host(s) you connected (`github` for github.com, `github-huit` for GHES).
- `gh` as a fallback when the MCP tools are not available.
- A one-line nudge at session start if `gh` is missing a login. It never blocks.
- Optionally, a narrow read-only `gh` allowlist in your `~/.claude/settings.json`
  so `gh pr view` and friends stop prompting. Writes always prompt. The skill
  offers this; nothing is added without your yes.

## Requirements

- Claude Code with plugin support.
- `gh` (GitHub CLI). The skill will offer to install it.
- For GHES only: `github-mcp-server` on your PATH (`brew install github-mcp-server`,
  or a release binary on Linux).

## Admin notes

- The github.com path uses GitHub's own MCP server and OAuth app. Because
  `harvard-huit` enforces SAML SSO, an org owner must authorize that OAuth app for
  the org once. Until then `/mcp` login for `github` will fail with an
  org-authorization error.
- This is separate from the GitHub connector setting in claude.ai. Claude Code's
  MCP configuration is local to the machine and authorizes directly against
  GitHub, not through Anthropic.

## Troubleshooting

- `github-huit` shows failed in `/mcp`: run the wrapper by hand to see why.
  Find the install path with `claude plugin list --json` (`installPath`), then run
  `<installPath>/bin/github-mcp-ghes.sh </dev/null`. Usual causes: no `gh` login
  for github.huit.harvard.edu, or the binary not on PATH.
- 403 mentioning SAML on github.com: `gh auth refresh --hostname github.com` and
  authorize the token for `harvard-huit`.
- Changed `.mcp.json` or hooks while developing: uninstall and reinstall the
  plugin; those files are read at install time.

## Layout

```
.claude-plugin/plugin.json      plugin manifest
.claude-plugin/marketplace.json single-plugin marketplace (source "./")
.mcp.json                       github (remote, OAuth) + github-huit (wrapper)
bin/github-mcp-ghes.sh          GITHUB_HOST + gh token -> github-mcp-server stdio
hooks/hooks.json                SessionStart -> scripts/check-gh-auth.sh
scripts/check-gh-auth.sh        login nudge, silent when all is well
skills/github-setup/SKILL.md    the bootstrap walkthrough
```

Validate before committing: `claude plugin validate .`
