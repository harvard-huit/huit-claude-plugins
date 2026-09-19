# huit-claude-plugins

Claude Code plugins for the AAIS group at Harvard University IT. This repo is
both the marketplace and the plugins.

| Plugin | What it does | Entry point |
|---|---|---|
| `huit-github` | GitHub access for both of our GitHubs **without a Personal Access Token** | `/huit-github:github-setup` |
| `huit-aws` | Log into HUIT AWS accounts with HarvardKey, from inside Claude Code | `/huit-aws:aws-login <account>` |

## Install

This repo is internal to the `harvard-huit` enterprise on github.com, so first
make sure `gh` is logged in there (`gh auth login --hostname github.com --web`).
Then, inside Claude Code:

```
/plugin marketplace add harvard-huit/huit-claude-plugins
/plugin install huit-github@huit-claude-plugins
/plugin install huit-aws@huit-claude-plugins
```

Install whichever you need. You approve every command a skill proposes.

## Updates

Claude Code checks marketplaces for updates shortly after a session starts and
tells you to run `/reload-plugins` when something changed, but only if
auto-update is enabled for this marketplace. It is off by default for
non-Anthropic marketplaces: open `/plugin`, find `huit-claude-plugins`, and turn
auto-update on. To update by hand:

```
/plugin marketplace update huit-claude-plugins
/plugin update huit-github@huit-claude-plugins
/plugin update huit-aws@huit-claude-plugins
/reload-plugins
```

## huit-github

Connects Claude to GitHub with OAuth logins you complete in your browser. No
PAT is created or stored.

| Host | Org | How it works |
|---|---|---|
| github.com | `harvard-huit` | GitHub's hosted MCP server, OAuth via `/mcp` |
| github.huit.harvard.edu (GHES) | `HUIT` | GitHub's `github-mcp-server` binary run locally, using the token from `gh auth login` |

Run `/huit-github:github-setup` and follow along. It checks what you already
have, installs `gh` (and `github-mcp-server` if you need GHES), runs
`gh auth login --web` for the host(s) you need, and has you run `/mcp` once to
authorize the github.com server.

You get MCP tools for issues, pull requests, repos, code search, and Actions on
whichever host(s) you connected (`github` for github.com, `github-huit` for
GHES), with `gh` as a fallback. A one-line nudge at session start tells you if
`gh` is missing a login; it never blocks. The skill can also offer a narrow
read-only `gh` allowlist for your `~/.claude/settings.json`; nothing is added
without your yes.

Requirements: `gh`. For GHES only, `github-mcp-server` on your PATH
(`brew install github-mcp-server` where Homebrew has a bottle for your OS,
otherwise the release binary from `github/github-mcp-server` in `~/.local/bin`;
the skill walks through both).

Admin notes: because `harvard-huit` enforces SAML SSO, an org owner must
authorize GitHub's MCP OAuth app for the org once; until then `/mcp` login for
`github` fails with an org-authorization error. This is separate from the
GitHub connector setting in claude.ai. Claude Code's MCP configuration is local
to the machine and authorizes directly against GitHub, not through Anthropic.

Troubleshooting: if `github-huit` shows failed in `/mcp`, run the wrapper by
hand to see why. Find the install path with `claude plugin list --json`
(`installPath`), then `<installPath>/bin/github-mcp-ghes.sh </dev/null`. Usual
causes: no `gh` login for github.huit.harvard.edu, or the binary not on PATH.
A 403 mentioning SAML on github.com means `gh auth refresh --hostname github.com`
and authorizing the token for `harvard-huit`.

## huit-aws

Gets you working AWS CLI credentials for HUIT accounts. HUIT federates
HarvardKey (Okta) straight to IAM roles, so there is no IAM Identity Center and
`aws sso login` does not apply. The skill wraps two tools:

| Tool | Best for | You do | Credentials last |
|---|---|---|---|
| HUIT `aws-login` CLI | every mapped account at once | approve one Okta Verify push | fixed, default 4 hours |
| `aws login` (AWS CLI 2.32+) | one long single-role session | log into the console in your browser, then click once | refreshed every 15 minutes while the console session lives |

Say "log me into admints-dev", run `/huit-aws:aws-login admints-dev`, or just
let an `aws` command fail with `ExpiredToken`; the skill picks up from there.
It checks what you have, chooses the branch, tells you what to do out of band
before each blocking step, and finishes with `aws sts get-caller-identity`.

Profile naming: `aws-login` aliases end in `-login` (`admints-dev-login`) and
`aws login` sessions use the plain account name (`admints-dev`). The two tools
must not share a profile name because static keys in `~/.aws/credentials` win
over an `aws login` session under the same name. The skill enforces this.

Requirements: AWS CLI 2.32 or newer for `aws login`; the HUIT `aws-login`
binary (releases on github.huit.harvard.edu, `HUIT/aws-login-saml-cli`) for
the one-push path. The skill can download it for you once `gh` is logged into
GHES. Okta Verify push must be enrolled. `aws-login configure_keyring` once,
in your own terminal, lets the skill run logins without a password prompt.

The skill never reads your credentials files and never prints keys.

## Layout

```
.claude-plugin/marketplace.json          the marketplace (two plugins)
plugins/huit-github/
  .claude-plugin/plugin.json             manifest
  .mcp.json                              github (remote, OAuth) + github-huit (wrapper)
  bin/github-mcp-ghes.sh                 GITHUB_HOST + gh token -> github-mcp-server stdio
  hooks/hooks.json                       SessionStart -> scripts/check-gh-auth.sh
  scripts/check-gh-auth.sh               login nudge, silent when all is well
  skills/github-setup/SKILL.md           the bootstrap walkthrough
plugins/huit-aws/
  .claude-plugin/plugin.json             manifest
  skills/aws-login/SKILL.md              the login walkthrough
```

Validate before committing:

```
claude plugin validate .
claude plugin validate plugins/huit-github
claude plugin validate plugins/huit-github/skills
claude plugin validate plugins/huit-aws
claude plugin validate plugins/huit-aws/skills
```

Bump the plugin's `version` on every change you publish; that field is what
tells installed copies an update exists.
