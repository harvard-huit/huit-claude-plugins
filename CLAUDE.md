# huit-claude-plugins

A self-hosting Claude Code plugin marketplace for the AAIS group / HUIT org.
Repo: `harvard-huit/huit-claude-plugins` (github.com, Internal). Marketplace
name: `huit-claude-plugins`. It holds two plugins: `huit-github`, which gives
people a working GitHub integration **without creating or storing a Personal
Access Token**, and `huit-aws`, which logs people into HUIT AWS accounts via
HarvardKey (see "huit-aws plugin" below). Onboarding is two slash commands per
plugin.

Status (2026-09-19): restructured to `plugins/<name>/`, both plugins validate
and install locally. The GHES path is verified end to end. Nothing is committed
or published yet.

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

1. **One repo is both the plugins and the marketplace.** `.claude-plugin/marketplace.json`
   at the root lists each plugin with `"source": "./plugins/<name>"`. Users run
   `/plugin marketplace add harvard-huit/huit-claude-plugins` then
   `/plugin install <name>@huit-claude-plugins`. Renamed 2026-09-19 from
   `huit-plugins` so the marketplace can grow beyond GitHub; the same day
   `huit-github` moved from the repo root to `plugins/huit-github/` (version
   0.1.0 to 0.2.0) when `huit-aws` was added.
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

## Layout

```
huit-claude-plugins/
├── .claude-plugin/
│   └── marketplace.json      # name: huit-claude-plugins, plugins: huit-github, huit-aws
├── plugins/
│   ├── huit-github/
│   │   ├── .claude-plugin/plugin.json   # name, version, description, author, repository
│   │   ├── .mcp.json                    # github (remote http, OAuth) + github-huit (wrapper script)
│   │   ├── bin/github-mcp-ghes.sh       # GITHUB_HOST + gh auth token -> github-mcp-server stdio
│   │   ├── hooks/hooks.json             # SessionStart -> scripts/check-gh-auth.sh
│   │   ├── scripts/check-gh-auth.sh
│   │   └── skills/github-setup/SKILL.md # install gh / MCP binary, device-flow login per host, /mcp, allowlist
│   └── huit-aws/
│       ├── .claude-plugin/plugin.json
│       └── skills/aws-login/SKILL.md    # aws-login login_all or aws login attach; see design below
├── README.md                 # user-facing: install, updates, one section per plugin
├── CLAUDE.md                 # this file
└── .claude/memory/INDEX.md   # committed project memory (portable across machines)
```

Inside each plugin, only `plugin.json` lives in `.claude-plugin/`; everything
else is at that plugin's root. Use `"${CLAUDE_PLUGIN_ROOT}"/bin/... ` (quoted)
in hook commands and `.mcp.json` so paths resolve after install. Skill `name`
in frontmatter is the invocation name (`/<plugin>:<skill>`); keep it stable.

## Open questions to settle first

- [x] **Does `gh auth login --hostname github.huit.harvard.edu --web` work?**
      Yes (verified 2026-09-19, gh 2.96.0): `gh api --hostname
      github.huit.harvard.edu user` returns the login, and `GH_HOST=... gh
      release download` works. The `Authorization: Bearer` 401 applies only to
      classic PATs, not to OAuth tokens from device-flow login. GHES shows
      3.19 in its API docs URL now, not 3.17.
- [x] **Does the local `github-mcp-server` work against that GHES with the `gh` token?**
      Yes (verified 2026-09-19, binary 1.12.2): the wrapper started with
      `host=https://github.huit.harvard.edu`, and `get_me` plus
      `search_repositories` succeeded over stdio using the `gh` OAuth token.
- [ ] **Does the remote server need a Copilot license or org policy?** Nothing
      documented says so, but confirm with a non-Copilot account.
- [ ] **Who authorizes the OAuth app for `harvard-huit` SAML?** Identify the org owner.
- [x] **Where does the marketplace repo live?** github.com
      `harvard-huit/huit-claude-plugins`, visibility Internal (visible to the
      enterprise, not public). Installing requires a github.com login that is
      SSO-authorized for `harvard-huit`, so `gh auth login --hostname github.com`
      comes before `/plugin marketplace add`.
- [x] **Does the local server's OAuth device-code fallback work for GHES?**
      Only with an OAuth App or GitHub App registered on the GHES instance and its
      client ID passed via `GITHUB_OAUTH_CLIENT_ID`; the baked-in app is github.com
      only. That is an admin ask we do not need, so the wrapper keeps using `gh`.

## huit-aws plugin

Log into HUIT AWS accounts from Claude Code. Wraps two tools rather than
replacing either: the HUIT `aws-login` binary (SAML via HarvardKey + Okta Verify
push; canonical repo `HUIT/aws-login-saml-cli` on GHES, github.com mirror
`harvard-huit/aws-login-saml-cli`) and the native `aws login` command (AWS CLI
2.32.0+). Skill first, hook second. The skill lives at
`plugins/huit-aws/skills/aws-login/SKILL.md` and is invoked as
`/huit-aws:aws-login <account>`. It was drafted as a personal skill on
2026-09-19 and moved here the same day; the personal copy was deleted so there
is one source of truth.

### Facts established 2026-09-19 (do not re-derive)

- **`aws sso login` does not apply.** HUIT federates SAML straight to IAM roles
  (`*-standard-saml-poweruser-iam-role`); there is no IAM Identity Center.
- **IAM SAML federation is IdP-initiated only.** AWS's sign-in page cannot
  redirect to Okta, so `aws login`'s "sign in to new session" button lands on the
  IAM-user page and is a dead end for us. There is no config key that accepts an
  IdP URL. `login_session` is an identity ARN
  (`arn:aws:sts::<acct>:assumed-role/<role>@<region>/<user>`), not a location.
- **The working `aws login` flow is: console session first, then attach.** Open
  the Okta embed link, finish HarvardKey and pick the role, then run
  `aws login --profile <alias>` and select the existing session in the browser.
  Confirmed working for one role; the role therefore already carries the
  `SignInLocalDevelopmentAccess` policy that `aws login` requires.
- **Okta embed link is per-app, not per-user**, so one URL serves everyone in
  HUIT with the AWS console app:
  `https://login.harvard.edu/home/harvard_awsconsole_1/0oa1u9wgsl3Ca8aIO1d8/aln1u9wlto0AtKDqe1d8`.
  Keep it as one named constant in the skill.
- **Trade-off between the two tools.** `aws-login login_all` gets every mapped
  profile from a single Okta push (best for multi-account). `aws login` needs
  one console login per role but refreshes credentials every 15 minutes for the
  life of the console session, bounded by the role's max session duration (best
  for a long single-role session). Console multi-session allows up to five role
  sessions in one browser, so several `aws login --profile` attachments are
  possible without logging out.
- **Both tools block on out-of-band action** (push approval or browser click).
  The skill must say so and not treat a long-running command as a hang.
- **`aws-login` surface (v2.0.x).** Subcommands: `login [alias]`, `login_all`,
  `list`, `list-role-map`, `switch <alias>`, `assume <alias>`,
  `configure_keyring`. Flags: `-version`, `-show-config` (prints the loaded
  config as JSON, creates an empty config file if none), `-h`, `-v`, `-t`,
  `-keyring=false`, `-d` (prints credentials, never use). **Bare `aws-login` is
  `login`**, which prompts for a password and a role picker. Config path is
  `~/Library/Application Support/huit_aws/config.json` on macOS and
  `~/.config/huit_aws/config.json` on Linux. Releases: 2.0.3 (2025-06, what is
  installed here), 2.0.4 (2026-05-19, latest stable), 2.1.0-beta1 (2026-06,
  adds browser `-passkey` login; prerelease). Local checkout at
  `~/workshop/aws-login-saml-cli` is at the 2025-06-09 commit.
- **Interactive prompts cannot be answered from Claude's Bash tool.** The
  `Enter Password:` prompt (no keyring), `login` without an alias (role picker),
  and `aws login --remote` (paste a code) all need the person's own terminal.
  With `configure_keyring` done, `login_all` needs only the push approval and
  runs fine from Claude.
- **Credential precedence gotcha (verified in bundled botocore, awscli 2.36.49).**
  Profile providers run in this order: web-identity, sso, shared-credentials-file,
  login, custom-process, config-file. So a `[<alias>]` stanza that `aws-login`
  wrote in `~/.aws/credentials` beats `login_session` for the same profile name in
  `~/.aws/config`, and once those static keys expire the profile fails with
  `ExpiredToken` even though the `aws login` session is healthy.
- **`aws login` auto-refresh confirmed 2026-09-19.** With
  `AWS_SHARED_CREDENTIALS_FILE=/dev/null` the `default` profile (where the test
  `login_session` landed, because `aws login` was run without `--profile`)
  resolved via the login provider and the cache expiry advanced by 15 minutes.
- **`gh release download` from GHES works** now that `gh` holds a GHES OAuth
  login, so the skill can offer the `aws-login` install without curl or a PAT.

### Skill design (`skills/aws-login/SKILL.md`)

- Two branches, chosen by the request:
  - "log into all my AWS profiles" or no alias given: `aws-login login_all`.
  - a named alias, or an `ExpiredToken` / `InvalidClientTokenId` error on an
    `aws` command: `open <okta-url>` (Mac) or print the URL (Linux), tell the
    user to finish the browser login, then on their go-ahead run
    `aws login --profile <alias>`. On a host without a browser (Cloud9) use
    `aws login --remote`.
- Always finish with `aws sts get-caller-identity --profile <alias>`.
- Read aliases from `aws-login list-role-map`; never hardcode a person's
  aliases or account IDs in the plugin.
- Prefer `aws-login switch <alias>` over re-authenticating when credentials for
  the alias are already cached.
- **Profile naming convention (decided 2026-09-19 by JaZahn):** `aws-login`
  aliases in `profile_map` end in `-login` (`admints-dev-login`), and `aws
  login` sessions use the plain account name (`admints-dev`). This avoids the
  precedence gotcha above. The skill checks for a static stanza under the plain
  name before attaching and, if one exists, offers to rename the aliases in the
  config rather than attaching under a colliding name.
- `aws-login` on macOS reads only `~/Library/Application Support/huit_aws/config.json`.
  `~/.huit_aws/config` (1.x) and `~/.config/huit_aws/config.json` may linger
  from older installs and are ignored there; the skill says so. The timeout
  key is `default_timeout_secs`; `default_timeout_sec` is silently ignored.
- The skill never edits `~/.aws/config` or `~/.aws/credentials` and never reads
  the credentials file or `~/.aws/login/cache/`; validity is checked with STS.

### To do

- [x] Draft the skill (2026-09-19), move `huit-github` to `plugins/huit-github/`
      and add `plugins/huit-aws/` (same day; `huit-github` bumped to 0.2.0).
- [ ] Use the skill against real logins for a while before publishing. Still
      unverified: whether `aws login --profile <new-name>` creates a
      `[profile ...]` stanza in `~/.aws/config` for a name that does not exist
      yet, and whether it writes `region`.
- [ ] Next `aws-login login_all` should write `*-login` stanzas only; confirm
      no plain-name stanza reappears in `~/.aws/credentials`.
- [ ] Test the single-alias branch on Cloud9: no `open`, must fall back to the
      printed URL and `aws login --remote`.
- [ ] Confirm `SignInLocalDevelopmentAccess` is on every standard SAML role, not
      just the one tested. If not, that is a HUIT cloud team ask; document who.
- [ ] Decide whether the credential check is a `SessionStart` nudge (matches
      `huit-github`) or a `PreToolUse` hook on `Bash` commands starting with
      `aws ` that fails fast with "run /aws-login" when credentials are expired.
      The PreToolUse form saves a wasted turn but is the first blocking hook in
      the marketplace; keep it silent when credentials are valid either way.
- [ ] Test the install story drafted in the skill on a clean machine:
      `GH_HOST=github.huit.harvard.edu gh release download -R HUIT/aws-login-saml-cli`
      with the `{Darwin,Linux}-{arm64,x86_64}` asset pattern, Gatekeeper
      `xattr` step, `~/bin` on PATH, then config.json from `aws-login list`.
- [x] Probe for installed vs configured: `aws-login -version` and
      `aws-login -show-config` (empty `profile_map` means not configured).

## Conventions

- Validate before every commit. Each `claude plugin validate <dir>` call checks
  one thing: the marketplace manifest for `.`, a plugin manifest for a plugin
  dir, and skill frontmatter for a `skills` dir. So run all five:
  `claude plugin validate .`, `... plugins/huit-github`, `... plugins/huit-aws`,
  `... plugins/huit-github/skills`, `... plugins/huit-aws/skills`.
- Test locally with `/plugin marketplace add ~/workshop/huit-claude-plugins` then
  `/plugin install <name>@huit-claude-plugins` (or the same via `claude plugin ...`
  on the CLI). Installs copy to `~/.claude/plugins/cache/huit-claude-plugins/<name>/<version>/`;
  `claude plugin list --json` shows `installPath`. The cache is a copy, not a
  link: after editing anything, `claude plugin uninstall` then `install` again
  (or bump the version). `.mcp.json` and hooks are read at install time; skills
  at session start. A local-path install copies gitignored files too, so nothing
  sensitive may sit in this tree.
- **Bump `version` in the plugin's `plugin.json` on every published change.**
  That field is the update signal: Claude Code refreshes marketplaces in the
  background after session start (when auto-update is enabled for the
  marketplace, which is off by default for non-Anthropic marketplaces) and
  prompts `/reload-plugins` when a version changed. Without a bump users keep
  the cached copy. Manual path: `/plugin marketplace update huit-claude-plugins`
  then `/plugin update <name>@huit-claude-plugins`. Admins can set
  `autoUpdate: true` on the marketplace entry in managed settings. No custom
  update-check hook; the built-in mechanism covers it.
- Scripts must be executable in git (`chmod +x`, and check `git ls-files -s`
  shows mode 100755); the installer preserves modes, it does not add them.
- Do not put a `.mcp.json` at the repo root. Claude Code reads a root
  `.mcp.json` as a *project* MCP config whenever this repo is the working
  directory, and `${CLAUDE_PLUGIN_ROOT}` is not expanded there, so a phantom
  `github-huit` failed with ENOENT in every session opened here until the
  plugin moved under `plugins/`.
- `brew install github-mcp-server` has no bottle on macOS versions Homebrew
  no longer supports (Tier 3, e.g. macOS 14) and exits without installing.
  The setup skill's fallback is the release tarball via
  `gh release download -R github/github-mcp-server` into `~/.local/bin`,
  checksum-verified. Tested 2026-09-19.
- Hook and wrapper scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, no
  Mac-only paths (this will run on Linux too). Never print tokens.
- Never put a token, hostname-specific secret, or a person's login in this repo.
- Memory routing: durable, portable, project-scoped facts go in
  `.claude/memory/` here (this repo is git-tracked). Machine-specific facts stay
  in `~/.claude` memory.
- `~/workshop/claude-plugins/` is an empty shell created the same morning, now
  superseded by this repo (which is the multi-plugin marketplace). Safe to delete.

## References

- Plugin reference: https://code.claude.com/docs/en/plugins-reference.md
- Marketplaces: https://code.claude.com/docs/en/plugin-marketplaces.md
- Managed MCP / managed settings (if admins later want to push this org-wide):
  https://code.claude.com/docs/en/managed-mcp.md
- GitHub MCP server (remote OAuth, local binary, `GITHUB_HOST`): https://github.com/github/github-mcp-server
- `gh auth login`: https://cli.github.com/manual/gh_auth_login
- HUIT GHES gotchas live in `~/.claude/memory/huit-github-enterprise-api.md`
