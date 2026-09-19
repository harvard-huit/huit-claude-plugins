---
name: aws-login
description: Log into HUIT AWS accounts from Claude Code, using the HUIT aws-login SAML CLI (HarvardKey + Okta Verify push) or the native `aws login` console-session attach. Use when the user asks to log into AWS, refresh or switch AWS credentials or profiles, asks which AWS account or role they are using, or when an aws command fails with ExpiredToken, InvalidClientTokenId, or "Unable to locate credentials".
---

# AWS login (HUIT)

You are getting one person working AWS CLI credentials for HUIT accounts. HUIT
federates HarvardKey (Okta) SAML straight to IAM roles. There is no IAM Identity
Center, so `aws sso login` and `aws configure sso` never apply here.

Two tools, two branches. Both block on something the person does outside the
terminal: approving an Okta Verify push, or clicking in a browser. A command
that sits silent for a minute is waiting, not hung. Run these with a long
timeout (five minutes) and tell the person what to do *before* you run them.

| Tool | Best for | Out-of-band step | Credential lifetime |
|---|---|---|---|
| `aws-login` (HUIT SAML CLI) | every mapped profile at once | one Okta Verify push | fixed (default 4h), no refresh |
| `aws login` (AWS CLI 2.32+) | one long single-role session | browser: console login, then one click | refreshed every 15 min for the life of the console session |

## Hard rules

- **Never run bare `aws-login`, and never `aws-login login` without an alias.**
  Bare `aws-login` *is* an interactive login: it prompts for a password and a
  role, and neither prompt can be answered from here. `aws-login -h`,
  `-version`, `-show-config`, `list-role-map`, `switch`, `login_all`, and
  `login <alias>` are the only forms you run.
- **Never use `aws-login -d`.** It prints credentials.
- **Never read `~/.aws/credentials` or `~/.aws/login/cache/`, and never run
  `aws configure export-credentials`.** Check validity with STS, not by looking
  at keys. `grep '^\['` on the credentials file (section names only) is fine.
- **Never hardcode aliases or account IDs.** Read them from
  `aws-login list-role-map`.
- **Do not edit `~/.aws/config` or `~/.aws/credentials` yourself.** Both tools
  write them. If an edit is needed, show the person the exact change.
- Shell state does not persist between your Bash calls, so `export AWS_PROFILE`
  does nothing useful. Pass `--profile <alias>` on every `aws` command.

## Constant

```
OKTA_AWS_CONSOLE=https://login.harvard.edu/home/harvard_awsconsole_1/0oa1u9wgsl3Ca8aIO1d8/aln1u9wlto0AtKDqe1d8
```

The per-app Okta embed link for the HUIT AWS console. It is not per-user; one
URL serves everyone with the app.

## 1. Inventory

Read-only. The only network call is STS. Summarize in a few lines.

```sh
command -v aws-login && aws-login -version
aws --version
aws-login -show-config 2>/dev/null | python3 -c 'import json,sys; c=json.load(sys.stdin); print("username set:", bool(c.get("username")), "| profiles:", ", ".join(sorted(c.get("profile_map",{}).values())) or "(none)")'
aws-login list-role-map
grep -E '^\[' ~/.aws/config ~/.aws/credentials 2>/dev/null
uname -s
```

Interpretation:

- `aws-login` missing: see "Install" below. `-show-config` with an empty
  `profile_map` means installed but not configured (note: `-show-config` creates
  an empty config file if none exists; that is harmless).
- `aws --version` below 2.32.0 has no `aws login`; only branch A is available.
- Aliases from `list-role-map` should end in `-login`; plain names are reserved
  for `aws login` sessions (see branch B step 1). When the person names an
  account (`admints-dev`), the `aws-login` alias is `admints-dev-login` and the
  `aws login` profile is `admints-dev`.
- Then check the profile the person cares about (or `default`):

```sh
aws sts get-caller-identity --profile <alias> --output json
```

If that succeeds, report the `Arn` and stop; nothing needs a login. If it fails
with `ExpiredToken`, `InvalidClientTokenId`, or `Unable to locate credentials`,
pick a branch.

## 2. Pick a branch

- **Branch A, `aws-login login_all`:** the person said "all", "everything",
  named several aliases, or named none. Also the fallback when `aws login` is
  unavailable or the console flow fails.
- **Branch B, `aws login` attach:** the person named one alias, or one
  profile's command failed, and they want a session that keeps refreshing.

If they name one alias but `aws-login` is installed and configured, ask which
they prefer in one line (one push for all profiles vs one browser login for a
long-lived single role). Default to B if they do not care.

## Branch A: all profiles with one Okta push

Say first: "This sends an Okta Verify push to your phone. Approve it when it
arrives." Then:

```sh
aws-login login_all
```

Run with a five-minute timeout.

- If the output contains `Enter Password:`, the OS keyring does not hold their
  password, so the command cannot proceed from here. Tell them to run
  `aws-login configure_keyring` once in their own terminal (stores the password
  in the OS keyring), then re-run this step. Alternatively they run
  `aws-login login_all` in their own terminal.
- `Could not find an Okta Verify (push) MFA option` usually follows an empty or
  wrong password (keyring not set up), or Okta Verify not enrolled. Check the
  keyring first.
- On success it prints `Logged in!` and writes every mapped profile
  (`<name>-login`) to `~/.aws/credentials`, plus `DEFAULT`.

To make one alias the default profile without re-authenticating:

```sh
aws-login switch <name>-login
```

Verify:

```sh
aws sts get-caller-identity --profile <name>-login --output json
```

## Branch B: attach `aws login` to a console session

`aws login` cannot start a HarvardKey login itself. IAM SAML federation is
IdP-initiated only, so the "sign in to a new session" button on AWS's page
leads to the IAM-user form and is a dead end. The person must be logged into
the console in their browser first; `aws login` then attaches to that session.

**Step 1: profile name.** The two tools must not share a profile name. The
AWS CLI checks the shared credentials file *before* the `login_session`
provider, so a static `[<name>]` stanza written by `aws-login` wins over an
`aws login` session under the same name, and once those keys expire the profile
fails with `ExpiredToken` even though the console session is fine.

Convention: `aws-login` aliases in the profile map end in `-login`
(`admints-dev-login`), and `aws login` uses the plain account name
(`admints-dev`). So the profile for this step is the plain name. Confirm no
collision before attaching:

```sh
grep -nE "^\[<profile>\]" ~/.aws/credentials
```

If that prints a line, the profile map does not follow the convention yet.
Show the person the `profile_map` values from `aws-login list-role-map` and
offer to rename them with a `-login` suffix in the config file (see
"Config file" below; update `required_profile` in `assumable_roles` to match).
Do not attach under a colliding name.

**Step 2: console login.** Open the Okta link and stop:

```sh
open "$OKTA_AWS_CONSOLE"          # macOS
xdg-open "$OKTA_AWS_CONSOLE"      # Linux with a desktop
```

With no browser on this host, print the URL for them to open elsewhere. Tell
them: complete HarvardKey and the Okta Verify push, pick the account and role
matching `<alias>` on the role chooser (show them the ARN from
`list-role-map`), wait for the console to load, then tell you "done". **End
your turn here.** Do not run the next command until they confirm.

**Step 3: attach.** Say: "A browser tab will open on AWS. Choose the console
session you just started and click Allow." Then, with a five-minute timeout:

```sh
aws login --profile <profile>
```

- The chooser lists existing console sessions (up to five). They pick the
  matching one. If they see an IAM-user sign-in form instead, that browser has
  no console session; go back to step 2.
- On a host without a browser (Cloud9, SSH), `aws login --remote --profile
  <profile>` prints a URL and then waits for a pasted code, which cannot be
  supplied from here. Print that exact command for the person to run in their
  own terminal, then continue at step 4.
- `AccessDenied` mentioning `SignInLocalDevelopmentAccess`: the role lacks the
  policy `aws login` requires. That is a HUIT cloud team ask; stop and say so.

**Step 4: verify.**

```sh
aws sts get-caller-identity --profile <profile> --output json
```

Report the `Arn`. If the CLI complains about a missing region, the new profile
stanza in `~/.aws/config` needs `region = us-east-1`; show them the two lines.

Credentials now refresh every 15 minutes for as long as the console session
lives, bounded by the role's maximum session duration. Repeat for another role
without logging out: console multi-session allows five roles in one browser.

## Assumable roles

If the config's `assumable_roles` lists the role they want (visible in
`-show-config`), the base profile must be valid first, then:

```sh
aws-login assume <role-alias>
```

## Install and configure (only when inventory shows a gap)

**`aws-login` binary.** Releases live on HUIT's GitHub Enterprise, so a GHES
login is required first: `gh auth login --hostname github.huit.harvard.edu --web`
(or the `github-setup` skill from the `huit-github` plugin). Then:

```sh
arch=$(uname -m); case "$arch" in aarch64) arch=arm64 ;; esac
GH_HOST=github.huit.harvard.edu gh release download -R HUIT/aws-login-saml-cli \
  -p "aws-login-saml-cli-*-$(uname -s)-${arch}.tar.gz" -D /tmp/aws-login-dl
tar -xzf /tmp/aws-login-dl/*.tar.gz -C /tmp/aws-login-dl
mkdir -p ~/bin && install -m 755 /tmp/aws-login-dl/aws-login ~/bin/aws-login
```

Asset names follow `aws-login-saml-cli-<ver>-{Darwin,Linux}-{arm64,x86_64}.tar.gz`.
`gh release download` takes the latest non-prerelease. `~/bin` must be on PATH.
On macOS, Gatekeeper blocks the first run: right-click, Open in Finder, or
`xattr -d com.apple.quarantine ~/bin/aws-login`.

**Config file.** `aws-login` reads:

| OS | Path |
|---|---|
| macOS | `~/Library/Application Support/huit_aws/config.json` |
| Linux | `~/.config/huit_aws/config.json` |

Only that path is read. `~/.huit_aws/config` is the 1.x location and
`~/.config/huit_aws/config.json` on macOS is ignored; edits there do nothing.
Verify any edit with `aws-login list-role-map`. Note the timeout key is
`default_timeout_secs`; a misspelling is silently ignored.

It needs `username` and a `profile_map` of role ARN (with `@<region>` suffix)
to alias, with aliases ending in `-login`. The ARNs come from `aws-login list`,
which needs an Okta login and a password prompt, so the person runs it in their
own terminal and pastes the list back; then offer to write the config for them.
Example shape:

```json
{
  "username": "someone@harvard.edu",
  "profile_map": {
    "arn:aws:iam::<account>:role/<name>-standard-saml-poweruser-iam-role@us-east-1": "<name>-login"
  }
}
```

If you edit this file for them, back it up first, parse the result as JSON
(hand edits often leave a trailing comma), and keep `required_profile` values
in `assumable_roles` in step with the renamed aliases.

**Keyring.** `aws-login configure_keyring` (their terminal, interactive) stores
the password so `login_all` needs only the push approval.

**AWS CLI.** `aws login` needs 2.32.0 or newer: `brew upgrade awscli` on macOS,
or AWS's installer elsewhere.

## Optional: narrow allowlist

Plugins cannot ship permissions. Offer (do not assume) to add these to the
person's `~/.claude/settings.json` `permissions.allow`, showing exactly what you
will add and waiting for a yes:

```json
"Bash(aws sts get-caller-identity:*)",
"Bash(aws-login -version:*)",
"Bash(aws-login -show-config:*)",
"Bash(aws-login list-role-map:*)"
```

Never add `Bash(aws:*)` or `Bash(aws-login:*)`: `aws` performs writes, and bare
`aws-login` is a login.

## Error to action

| Seen | Meaning | Do |
|---|---|---|
| `ExpiredToken`, `InvalidClientTokenId` | credentials stale | branch A or B |
| `Unable to locate credentials` | profile has no credentials or does not exist | compare the name against `list-role-map`; then A or B |
| `Enter Password:` from `aws-login` | keyring not configured | person runs `aws-login configure_keyring` |
| `Could not find an Okta Verify (push) MFA option` | empty or wrong password, or Okta Verify not enrolled | keyring first, then Okta enrollment |
| `aws login` shows an IAM-user form | no console session in that browser | back to branch B step 2 |
| `AccessDenied` with `SignInLocalDevelopmentAccess` | role lacks the policy | HUIT cloud team ask |
| profile works with static file hidden but not normally | name collision, stale static keys | rename the `aws-login` alias to `<name>-login` |
| `list-role-map` shows edits missing | wrong config file edited | only the path in the table below is read; `~/.huit_aws/config` is the 1.x location |
