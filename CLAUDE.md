# huit-github-plugin

A Claude Code plugin that gives people in the AAIS group / HUIT org a working
GitHub integration **without creating or storing a Personal Access Token**.
Distributed as a self-hosting plugin marketplace (one git repo, one plugin) so
onboarding is two slash commands.

Status (2026-09-19): every file in the layout below exists, validates, and
installs locally. Nothing is committed or published yet, and the GHES path is
untested against the real host (see open questions).

@.claude/memory/INDEX.md

## Why this exists

- The org has not approved the GitHub connector in claude.ai. That is a Claude
  admin setting for claude.ai; Claude Code's MCP config is separate and local.
  Adding GitHub's MCP server here does OAuth directly against GitHub, not through
  Anthropic. Be transparent with the admins about this rather than treating it as
  a workaround. Ask before publishing to the org.
- Current practice is PAT-based (`GITHUB_PAT`, `GITHUB_HUIT_PAT` in
  `~/.claude/.credentials.env`). PATs are long-lived, over-scoped, and each person
  has to make and guard their own. Goal is zero PATs for plugin users.

## Two GitHubs, two auth paths

| Host | Org | Remote MCP (OAuth) | `gh` device-flow login | Local MCP binary |
|---|---|---|---|---|
| github.com | `harvard-huit` (SAML SSO) | yes, primary path | yes | not needed |
| github.huit.harvard.edu (GHES 3.17) | `HUIT` | **no** (GHES has no remote hosting) | untested, see below | yes, via `GITHUB_HOST` |

Some repos are live on GHES while the github.com copy is a stale mirror. Check
`pushed_at` on both before assuming which is canonical. Cross-instance `#N`
references do not auto-link.

## Design decisions (made 2026-09-19)

1. **One repo is both the plugin and the marketplace.** `.claude-plugin/marketplace.json`
   lists a single plugin with `"source": "./"`. Users run
   `/plugin marketplace add <git url>` then `/plugin install huit-github@huit-plugins`.
   Marketplace name is provisional.
2. **github.com path is the remote GitHub MCP server over HTTP with OAuth.**
   Declared in plugin-root `.mcp.json` as `{"type": "http", "url": "https://api.githubcopilot.com/mcp/"}`.
   User authenticates once via `/mcp`. Because `harvard-huit` enforces SAML, an
   org owner must authorize the OAuth app for the org one time. That is the
   only admin ask on this path.
3. **GHES path is the local `github-mcp-server` binary behind a wrapper script.**
   `bin/github-mcp-ghes.sh` sets `GITHUB_HOST=https://github.huit.harvard.edu`,
   pulls the token from `gh auth token --hostname github.huit.harvard.edu`, and
   execs `github-mcp-server stdio`. The binary is on Homebrew (`github-mcp-server`,
   1.12.x at time of writing) and Docker. No PAT: the token comes from `gh`'s
   OAuth device-flow login.
4. **A `github-setup` skill does the bootstrap.** It checks for `gh` and the MCP
   binary, offers the install commands (brew on Mac, apt/dnf otherwise), runs
   `gh auth login --hostname <host> --web` for whichever host the person needs,
   and tells them to run `/mcp` for the github.com OAuth. A skill cannot install
   anything itself; it instructs Claude, and the user approves each command.
5. **A `SessionStart` hook nudges, never blocks.** `hooks/hooks.json` runs a
   script that checks `gh auth status` for both hosts and prints a one-line hint
   if either is missing. It must exit 0 quickly and be silent when all is well.
6. **Permissions are NOT shipped in the plugin.** Plugin-root `settings.json`
   only supports `agent` and `subagentStatusLine`; permission keys are rejected.
   So the plugin cannot pre-allow `Bash(gh *)`. Instead the setup skill offers to
   add a narrow read-only allowlist to the user's `~/.claude/settings.json`
   (e.g. `Bash(gh pr view *)`, `Bash(gh pr list *)`, `Bash(gh issue view *)`,
   `Bash(gh issue list *)`, `Bash(gh repo view *)`, `Bash(gh api *)` read-only).
   Writes should keep prompting. Never allow bare `Bash(gh *)`.
7. **`gh` is the fallback when MCP tools are unavailable.** Skill guidance should
   prefer MCP tools when the server is connected and fall back to `gh` otherwise,
   so the plugin still works for someone who only did the `gh` login.

## Planned layout

```
huit-github-plugin/
├── .claude-plugin/
│   ├── plugin.json           # name, version, description, author, repository
│   └── marketplace.json      # name: huit-plugins, plugins: [{name: huit-github, source: "./"}]
├── .mcp.json                 # github (remote http, OAuth) + github-huit (wrapper script)
├── bin/
│   └── github-mcp-ghes.sh    # GITHUB_HOST + gh auth token -> github-mcp-server stdio
├── hooks/
│   ├── hooks.json            # SessionStart -> scripts/check-gh-auth.sh
├── scripts/
│   └── check-gh-auth.sh
├── skills/
│   └── github-setup/
│       └── SKILL.md          # install gh / MCP binary, device-flow login per host, /mcp, allowlist
├── README.md                 # user-facing: two commands to install, what to expect
├── CLAUDE.md                 # this file
└── .claude/memory/INDEX.md   # committed project memory (portable across machines)
```

Only `plugin.json` lives inside `.claude-plugin/`. Everything else is at plugin
root. Use `"${CLAUDE_PLUGIN_ROOT}"/bin/... ` (quoted) in hook commands and
`.mcp.json` so paths resolve after install. Skill `name` in frontmatter is the
invocation name; keep it stable.

## Open questions to settle first

- [ ] **Does `gh auth login --hostname github.huit.harvard.edu --web` work?**
      Known gotcha: `gh` with a classic PAT fails there with 401 because it sends
      `Authorization: Bearer` and that GHES rejects it for classic PATs. An OAuth
      token from device-flow login may behave differently. Test this before
      promising GHES support. If it fails, the GHES fallback is a curl-based skill
      using `Authorization: token`.
- [ ] **Does the local `github-mcp-server` work against that GHES with the `gh` token?**
      Same Bearer question applies to the binary.
- [ ] **Does the remote server need a Copilot license or org policy?** Nothing
      documented says so, but confirm with a non-Copilot account.
- [ ] **Who authorizes the OAuth app for `harvard-huit` SAML?** Identify the org owner.
- [x] **Where does the marketplace repo live?** github.com
      `harvard-huit/huit-github-plugin`, visibility Internal (visible to the
      enterprise, not public). Installing requires a github.com login that is
      SSO-authorized for `harvard-huit`, so `gh auth login --hostname github.com`
      comes before `/plugin marketplace add`.
- [x] **Does the local server's OAuth device-code fallback work for GHES?**
      Only with an OAuth App or GitHub App registered on the GHES instance and its
      client ID passed via `GITHUB_OAUTH_CLIENT_ID`; the baked-in app is github.com
      only. That is an admin ask we do not need, so the wrapper keeps using `gh`.

## Conventions

- Validate before every commit. `claude plugin validate .` only checks the
  marketplace manifest when both manifests exist, so run all three:
  `claude plugin validate .`, `claude plugin validate .claude-plugin/plugin.json`,
  `claude plugin validate skills`. `--strict` warns that a root `CLAUDE.md` is not
  loaded as plugin context; that is expected, it is for developers of this repo.
- Test locally with `/plugin marketplace add ~/workshop/huit-github-plugin` then
  `/plugin install huit-github@huit-plugins` (or the same via `claude plugin ...`
  on the CLI). Installs copy to `~/.claude/plugins/cache/huit-plugins/huit-github/<version>/`;
  `claude plugin list --json` shows `installPath`. Uninstall and reinstall after
  changing `.mcp.json` or hooks; those are read at install time. A local-path
  install copies gitignored files too, so nothing sensitive may sit in this tree.
- Scripts must be executable in git (`chmod +x`, and check `git ls-files -s`
  shows mode 100755); the installer preserves modes, it does not add them.
- Hook and wrapper scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, no
  Mac-only paths (this will run on Linux too). Never print tokens.
- Never put a token, hostname-specific secret, or a person's login in this repo.
- Memory routing: durable, portable, project-scoped facts go in
  `.claude/memory/` here (this repo is git-tracked). Machine-specific facts stay
  in `~/.claude` memory.
- Related, unrelated to this repo: `~/workshop/claude-plugins/` is an empty shell
  created the same morning. If this grows into several plugins, that is the
  natural home for a multi-plugin marketplace; this repo would become
  `plugins/huit-github/` under it.

## References

- Plugin reference: https://code.claude.com/docs/en/plugins-reference.md
- Marketplaces: https://code.claude.com/docs/en/plugin-marketplaces.md
- Managed MCP / managed settings (if admins later want to push this org-wide):
  https://code.claude.com/docs/en/managed-mcp.md
- GitHub MCP server (remote OAuth, local binary, `GITHUB_HOST`): https://github.com/github/github-mcp-server
- `gh auth login`: https://cli.github.com/manual/gh_auth_login
- HUIT GHES gotchas live in `~/.claude/memory/huit-github-enterprise-api.md`
