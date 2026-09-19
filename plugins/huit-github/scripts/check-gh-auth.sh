#!/usr/bin/env bash
# SessionStart hook: nudge, never block.
#
# Checks whether `gh` holds a login for github.com and for HUIT's GHES. Prints
# nothing when both are present. Otherwise emits one JSON object whose
# systemMessage is shown to the user and whose additionalContext lets Claude
# offer the github-setup skill. Always exits 0. No network calls: `gh auth
# token` only reads the local keyring, so this stays fast and works offline.
set -uo pipefail

GHES_HOST="${HUIT_GHES_HOST:-github.huit.harvard.edu}"
SETUP_CMD="/huit-github:github-setup"

# Drain stdin (hook input JSON) so the parent never blocks on a full pipe.
cat >/dev/null 2>&1 || true

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin"

emit() {
  # $1: one-line message. Fixed strings only; nothing user-controlled reaches
  # the JSON, so no escaping is needed beyond what's written here.
  printf '{"systemMessage":"huit-github: %s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"huit-github plugin: %s If the user asks about GitHub, offer to run the github-setup skill (%s). Do not run it unprompted."}}\n' \
    "$1" "$1" "$SETUP_CMD"
}

if ! command -v gh >/dev/null 2>&1; then
  emit "gh is not installed, so the GitHub integration cannot authenticate. Run $SETUP_CMD to set it up."
  exit 0
fi

missing=()
gh auth token --hostname github.com >/dev/null 2>&1 || missing+=("github.com")
gh auth token --hostname "$GHES_HOST" >/dev/null 2>&1 || missing+=("$GHES_HOST")

case "${#missing[@]}" in
  0) exit 0 ;;
  1) emit "gh has no login for ${missing[0]}. Run $SETUP_CMD if you need that host." ;;
  *) emit "gh has no login for github.com or $GHES_HOST. Run $SETUP_CMD to connect GitHub." ;;
esac
exit 0
