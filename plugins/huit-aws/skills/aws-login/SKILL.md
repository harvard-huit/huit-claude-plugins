---
name: aws-login
description: Log into HUIT AWS accounts from Claude Code. Default is the native `aws login` console-session attach into the `default` profile (HarvardKey in the browser, pick any account and role, credentials refresh every 15 minutes), also refreshing any saved profile that points at the same session; the HUIT aws-login SAML CLI (one Okta Verify push, every mapped profile) is the "all profiles" path. Use when the user asks to log into AWS, refresh or switch AWS credentials or profiles, asks which AWS account or role they are using, or when an aws command fails with ExpiredToken, InvalidClientTokenId, or "Unable to locate credentials".
---

# AWS login (HUIT)

You are getting one person working AWS CLI credentials for HUIT accounts. HUIT
federates HarvardKey (Okta) SAML straight to IAM roles. There is no IAM Identity
Center, so `aws sso login` and `aws configure sso` never apply here.

Two tools, two branches. Both block on something the person does outside the
terminal: clicking in a browser, or approving an Okta Verify push. A command
that sits silent for a minute is waiting, not hung. Run these with a long
timeout (five minutes) and tell the person what to do *before* you run them.

| Tool | Best for | Out-of-band step | Credential lifetime |
|---|---|---|---|
| `aws login` (AWS CLI 2.32+), **the default** | the `default` profile, or one named profile | browser: console login, then one click | refreshed every 15 min for the life of the console session |
| `aws-login` (HUIT SAML CLI) | every mapped profile at once | one Okta Verify push | fixed (default 4h), no refresh |

## Hard rules

- **Never run bare `aws-login`, `aws-login login`, `aws-login login <alias>`,
  or `aws-login switch`.** Bare `aws-login` *is* an interactive login: it
  prompts for a password and a role, and neither prompt can be answered from
  here. `login <alias>` and `switch` write static keys into `[default]` in
  `~/.aws/credentials`, which shadows the `aws login` session in `default`
  and makes the next `aws login` refuse to run (see branch B step 1). The
  only `aws-login` forms you run: `-h`, `-version`, `-show-config`,
  `list-role-map`, `login_all`, `assume <alias>`.
- **Never use `aws-login -d`.** It prints credentials.
- **Never read `~/.aws/credentials` or `~/.aws/login/cache/`, and never run
  `aws configure export-credentials`.** Check validity with STS, not by looking
  at keys. Section names and key *names* from the credentials file are fine
  (the `awk` in "Inventory" prints no values).
- **Never hardcode aliases or account IDs.** Read them from
  `aws-login list-role-map` and `aws configure list-profiles`.
- **Do not edit `~/.aws/config` or `~/.aws/credentials` yourself.** Both tools
  write them. If an edit is needed, show the person the exact change.
- Shell state does not persist between your Bash calls, and the person's
  shell may export `AWS_PROFILE`, so **always pass `--profile <name>`**, even
  for `default`, on `aws login` and every `aws` command.

## Constant

```
OKTA_AWS_CONSOLE=https://login.harvard.edu/home/harvard_awsconsole_1/0oa1u9wgsl3Ca8aIO1d8/aln1u9wlto0AtKDqe1d8
```

The per-app Okta embed link for the HUIT AWS console. It is not per-user; one
URL serves everyone with the app.

## 1. Inventory

Read-only. The only network call is STS. Summarize in a few lines.

```sh
aws --version
command -v aws-login && aws-login -version
aws-login -show-config 2>/dev/null | python3 -c 'import json,sys; c=json.load(sys.stdin); print("username set:", bool(c.get("username")), "| profiles:", ", ".join(sorted(c.get("profile_map",{}).values())) or "(none)")'
aws-login list-role-map
aws configure list-profiles
for p in $(aws configure list-profiles); do s=$(aws configure get login_session --profile "$p" 2>/dev/null) && echo "$p -> $s"; done
awk '/^\[/{s=$0} /^aws_access_key_id/{print s, "has static keys"}' ~/.aws/credentials 2>/dev/null
uname -s
```

Interpretation:

- `aws --version` below 2.32.0 has no `aws login`; only branch A is available.
- `aws-login` missing is fine for branch B. Mention "Install" below only if the
  person wants branch A. `-show-config` with an empty `profile_map` means
  installed but not configured (it creates an empty config file if none
  exists; harmless).
- The `login_session` loop shows which profiles are `aws login` sessions and
  which console identity (`arn:aws:sts::<acct>:assumed-role/<role>@<region>/<user>`)
  each points at. Profiles that share a value share one credential cache.
- The `awk` line shows which profiles hold static keys written by `aws-login`.
  By convention those are `<name>-login`; plain names (`admints-dev`) and
  `default` belong to `aws login`. A `[default]` with static keys is the
  collision handled in branch B step 1.
- Then check the profile the person cares about (or `default`):

```sh
aws sts get-caller-identity --profile <profile> --output json
```

If that succeeds, report the `Arn` and stop; nothing needs a login. If it fails
with `ExpiredToken`, `InvalidClientTokenId`, or `Unable to locate credentials`,
pick a branch.

## 2. Pick a branch

- **Branch B, `aws login` (default):** the person named no profile (target is
  `default`, they pick the account and role in the browser), or named one
  profile (target is that name), or one profile's command failed.
- **Branch A, `aws-login login_all`:** the person said "all", "everything",
  "every account", named several profiles, or asked for `aws-login` or "the
  push" by name. Also the fallback when `aws login` is unavailable or the
  console flow fails.

Do not ask which they prefer. Say which branch you are taking in one line and
go; they can redirect you.

## Branch B: attach `aws login` to a console session

`aws login` cannot start a HarvardKey login itself. IAM SAML federation is
IdP-initiated only, so the "sign in to a new session" button on AWS's page
leads to the IAM-user form and is a dead end. The person logs into the console
in their browser first; `aws login` then attaches to that session and writes
`login_session = <console identity ARN>` into the target profile in
`~/.aws/config`. Credentials are cached under a hash of that ARN, not the
profile name, so every profile with the same `login_session` is refreshed by
one attach.

`<profile>` below is `default` when no profile was named.

**Step 1: preconditions on the target profile.** Two things block `aws login`
and neither can be fixed from here without the person.

*Static keys under the same name.* The AWS CLI checks the shared credentials
file *before* the `login_session` provider, so a static `[<profile>]` stanza
written by `aws-login` wins over the session, fails with `ExpiredToken` once
the keys age out, and makes `aws login --profile <profile>` refuse with
`Profile '<profile>' is already configured with Access Key credentials` (the
check merges the credentials file into the profile). If the inventory `awk`
flagged `[<profile>]`:

- For `default`: show the person the change, which is to delete (or rename to
  something like `[default-static-old]`) the `[default]` section in
  `~/.aws/credentials`. Say that `aws-login login <alias>` and `aws-login
  switch` re-create it, which is why this skill never runs them; `login_all`
  does not touch `default`.
- For a plain name: the `aws-login` profile map does not follow the `-login`
  convention yet. Show the `profile_map` values from `list-role-map` and offer
  to rename them with a `-login` suffix in the config file (see "Config file"
  below; update `required_profile` in `assumable_roles` to match). Do not
  attach under a colliding name.

Wait for them to confirm the edit, then continue.

*A different session already in the profile.* If the inventory shows
`<profile>` already has a `login_session`, `aws login` asks
`Do you want to overwrite it ... (y/n)` on stdin, which from here is EOF and a
traceback. Tell the person which role `default` currently points at and that
it will be replaced, then use the `printf 'y\n' |` form in step 3. The old
session's cache is not deleted; other profiles pointing at it keep working.

**Step 2: console login.** Open the Okta link and stop:

```sh
open "$OKTA_AWS_CONSOLE"          # macOS
xdg-open "$OKTA_AWS_CONSOLE"      # Linux with a desktop
```

With no browser on this host, print the URL for them to open elsewhere. Tell
them: complete HarvardKey and the Okta Verify push, pick the account and role
they want on the role chooser (for a named profile, the one matching it; show
the ARN from `list-role-map` if there is one), wait for the console to load,
then tell you "done". **End your turn here.** Do not run the next command
until they confirm.

**Step 3: attach.** Say: "A browser tab will open on AWS. Choose the console
session you just started and click Allow." Then, with a five-minute timeout:

```sh
aws login --profile <profile>
# or, when step 1 found a different session already in <profile>:
printf 'y\n' | aws login --profile <profile>
```

- The chooser lists existing console sessions (up to five). They pick the
  matching one. If they see an IAM-user sign-in form instead, that browser has
  no console session; go back to step 2.
- On success it prints `Updated profile <profile> to use <ARN> credentials.`
  That ARN is the console identity they chose; keep it for step 5.
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

Report the `Arn`. If the CLI complains about a missing region, the profile
stanza in `~/.aws/config` needs `region = us-east-1`; show them the two lines.

**Step 5: refresh matching saved profiles.** The role name in the ARN is
`<name>-standard-saml-poweruser-iam-role`; `<name>` is the account (for
example `admints-dev`). Compare the new session against every profile:

```sh
new=$(aws configure get login_session --profile <profile>)
for p in $(aws configure list-profiles); do
  [ "$p" = "<profile>" ] && continue
  s=$(aws configure get login_session --profile "$p" 2>/dev/null) || continue
  [ "$s" = "$new" ] && echo "$p: same session (refreshed)" || echo "$p: different session"
done
```

Then, in order:

- **Same `login_session`:** already refreshed by this attach (shared cache).
  Confirm with `aws sts get-caller-identity --profile <p>` and say so.
- **`[profile <name>]` exists with a different or no `login_session`:** offer
  `aws login --profile <name>`. It is one more browser click on the same
  console session; no new HarvardKey login. Use the `printf 'y\n' |` form if
  it holds a different session.
- **No `[profile <name>]`, but `list-role-map` has `<name>-login` for this
  account and role:** offer to create the plain-name profile the same way.
  Only if they want it.
- **`<name>-login` (static keys from `aws-login`):** `aws login` cannot
  refresh it. Say so once; if they want those refreshed too, that is branch A
  (one push refreshes every mapped alias).

Credentials now refresh every 15 minutes for as long as the console session
lives, bounded by the role's maximum session duration. Repeat for another role
without logging out: console multi-session allows five roles in one browser.

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
  (`<name>-login`) to `~/.aws/credentials`. It does not write `default`, so it
  coexists with an `aws login` session there.

Do not offer `aws-login switch` to make an alias the default: it copies static
keys into `[default]` and breaks branch B. If they want `default` to be a
particular role, that is branch B.

Verify:

```sh
aws sts get-caller-identity --profile <name>-login --output json
```

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
"Bash(aws configure list-profiles:*)",
"Bash(aws configure get login_session:*)",
"Bash(aws-login -version:*)",
"Bash(aws-login -show-config:*)",
"Bash(aws-login list-role-map:*)"
```

Never add `Bash(aws:*)` or `Bash(aws-login:*)`: `aws` performs writes, and bare
`aws-login` is a login.

## Error to action

| Seen | Meaning | Do |
|---|---|---|
| `ExpiredToken`, `InvalidClientTokenId` | credentials stale | branch B (or A for "all") |
| `Unable to locate credentials` | profile has no credentials or does not exist | compare the name against `list-role-map` and `list-profiles`; then B or A |
| `Profile 'X' is already configured with Access Key credentials` from `aws login` | static `[X]` stanza in `~/.aws/credentials` | branch B step 1: person removes or renames the stanza |
| `Do you want to overwrite it ... (y/n)` then `EOFError` from `aws login` | profile already has a different `login_session` | re-run as `printf 'y\n' \| aws login --profile X` after telling them |
| `Enter Password:` from `aws-login` | keyring not configured | person runs `aws-login configure_keyring` |
| `Could not find an Okta Verify (push) MFA option` | empty or wrong password, or Okta Verify not enrolled | keyring first, then Okta enrollment |
| `aws login` shows an IAM-user form | no console session in that browser | back to branch B step 2 |
| `AccessDenied` with `SignInLocalDevelopmentAccess` | role lacks the policy | HUIT cloud team ask |
| profile works with `AWS_SHARED_CREDENTIALS_FILE=/dev/null` but not normally | name collision, stale static keys | rename the `aws-login` alias to `<name>-login`, or remove static `[default]` |
| `list-role-map` shows edits missing | wrong config file edited | only the path in the table above is read; `~/.huit_aws/config` is the 1.x location |
