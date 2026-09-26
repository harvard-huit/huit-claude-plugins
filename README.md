# huit-agent-plugins

Claude Code plugins for the AAIS group at Harvard University IT. This repo is
both the marketplace and the plugins.

| Plugin | What it does | Entry point |
|---|---|---|
| `huit-github` | GitHub access for both of our GitHubs **without a Personal Access Token** | `/huit-github:github-setup` |
| `huit-aws` | Log into HUIT AWS accounts with HarvardKey, from inside Claude Code | `/huit-aws:aws-login <account>` |
| `quiz` | Multiple-choice comprehension checks on the current session or on the repo's gotchas | `/quiz:session`, `/quiz:project` |

## Install

This repo is internal to the `harvard-huit` enterprise on github.com, so first
make sure `gh` is logged in there (`gh auth login --hostname github.com --web`).
Then, inside Claude Code:

```
/plugin marketplace add harvard-huit/huit-agent-plugins
/plugin install huit-github@huit-agent-plugins
/plugin install huit-aws@huit-agent-plugins
/plugin install quiz@huit-agent-plugins
```

Install whichever you need. You approve every command a skill proposes.

## Updates

Claude Code checks marketplaces for updates shortly after a session starts and
tells you to run `/reload-plugins` when something changed, but only if
auto-update is enabled for this marketplace. It is off by default for
non-Anthropic marketplaces: open `/plugin`, find `huit-agent-plugins`, and turn
auto-update on. To update by hand:

```
/plugin marketplace update huit-agent-plugins
/plugin update huit-github@huit-agent-plugins
/plugin update huit-aws@huit-agent-plugins
/plugin update quiz@huit-agent-plugins
/reload-plugins
```

## huit-github

Connects Claude to GitHub with OAuth logins you complete in your browser. No
PAT is created or stored.

| Host | Org | How it works |
|---|---|---|
| github.com | `harvard-huit` | GitHub's hosted MCP server, sent the token from `gh auth login` on each connection |
| github.huit.harvard.edu (GHES) | `HUIT` | GitHub's `github-mcp-server` binary run locally, using the token from `gh auth login` |

Run `/huit-github:github-setup` and follow along. It checks what you already
have, installs `gh` (and `github-mcp-server` if you need GHES), and runs
`gh auth login --web` for the host(s) you need. That login is the whole
authentication step; there is no separate `/mcp` login. Restart Claude Code
after a new login so the MCP servers pick it up.

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

Admin notes: no admin action is required. Both servers use the token GitHub
CLI's own OAuth app issued at `gh auth login`, which `harvard-huit` already
accepts. This is separate from the GitHub connector setting in claude.ai.
Claude Code's MCP configuration is local to the machine and authenticates
directly against GitHub, not through Anthropic.

Why not the hosted server's own OAuth: choosing `github` in `/mcp` fails with
"Incompatible auth server: does not support dynamic client registration".
GitHub's authorization server does not implement Dynamic Client Registration,
which Claude Code's MCP OAuth flow needs. The plugin sidesteps it with a
`headersHelper` script that hands Claude Code the `gh` token instead.

Troubleshooting: if a server shows failed in `/mcp`, run its script by hand to
see why. Find the install path with `claude plugin list --json`
(`installPath`), then `<installPath>/bin/github-mcp-ghes.sh </dev/null` for
GHES, or `<installPath>/bin/github-mcp-headers.sh | sed -E 's/Bearer .*/Bearer <redacted>/'`
for github.com (keep the `sed`; the raw output is your token). Usual causes:
no `gh` login for that host, or the GHES binary not on PATH. A 403 mentioning
SAML on github.com means `gh auth refresh --hostname github.com` and
authorizing the token for `harvard-huit`. If `GH_TOKEN` or `GITHUB_TOKEN` is
exported in your shell, `gh` (and therefore both servers) uses that instead of
the keyring login.

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

## quiz

Three or four multiple-choice questions, answered in Claude Code's select UI,
graded in a sentence each. The point is not the score; it is finding out what
you did not know while it is still cheap to look.

| Skill | Asks about | Say |
|---|---|---|
| `/quiz:session` | what happened in this session: changes you approved without reading, decisions Claude made for you, security-relevant edits, loose ends | "quiz me", "did I miss anything" |
| `/quiz:project` | the gotchas of the repo you are in: rules in `CLAUDE.md`, decisions reversed in git history, setup traps, "do not" comments | "quiz me on this repo", "what should I know before I touch this" |

A bare "quiz me" means the session quiz, unless the session was too small to
have anything in it or was spent learning the project rather than changing it;
then you get the project quiz. Claude also offers the session quiz on its own
after a significant change lands. An argument narrows either quiz, e.g.
`/quiz:session security` or `/quiz:project setup`.

Neither skill changes anything. The project quiz reads files and git history;
in a large repo it uses a read-only subagent for the scan.

## Layout

```
.claude-plugin/marketplace.json          the marketplace (three plugins)
plugins/huit-github/
  .claude-plugin/plugin.json             manifest
  .mcp.json                              github (hosted, headersHelper) + github-huit (wrapper)
  bin/github-mcp-headers.sh              gh token -> Authorization header for the hosted server
  bin/github-mcp-ghes.sh                 GITHUB_HOST + gh token -> github-mcp-server stdio
  hooks/hooks.json                       SessionStart -> scripts/check-gh-auth.sh
  scripts/check-gh-auth.sh               login nudge, silent when all is well
  skills/github-setup/SKILL.md           the bootstrap walkthrough
plugins/huit-aws/
  .claude-plugin/plugin.json             manifest
  skills/aws-login/SKILL.md              the login walkthrough
plugins/quiz/
  .claude-plugin/plugin.json             manifest
  references/quiz-format.md              question style, asking, grading (shared by both skills)
  skills/session/SKILL.md                what happened in this session
  skills/project/SKILL.md                gotchas of the repo you are in
```

Validate before committing:

```
claude plugin validate .
claude plugin validate plugins/huit-github
claude plugin validate plugins/huit-github/skills
claude plugin validate plugins/huit-aws
claude plugin validate plugins/huit-aws/skills
claude plugin validate plugins/quiz
claude plugin validate plugins/quiz/skills
```

Bump the plugin's `version` on every change you publish; that field is what
tells installed copies an update exists.
