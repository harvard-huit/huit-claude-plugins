---
name: marketplace-update-vs-plugin-list
description: "Check for updates" refreshes the marketplace clone but the plugin picker is stale until /reload-plugins or a new session; how to verify the clone has the new plugin
metadata:
  type: project
---

Adding a plugin to `marketplace.json` and pushing does not make it appear in
the plugin picker of a running session, even after the desktop app's
"Manage marketplaces, check for updates" (seen 2026-09-26 with the `quiz`
plugin).

**Why:** "Check for updates" does a `git pull` of the marketplace clone at
`~/.claude/plugins/marketplaces/<marketplace>/` and bumps `lastUpdated` in
`~/.claude/plugins/known_marketplaces.json`, but the plugin list shown in the
UI is built when the session starts and is not re-read from that clone.

**How to apply:** before removing and re-adding the marketplace, check the
clone: `git log -1` in it should show the pushed commit and its
`.claude-plugin/marketplace.json` should list the new plugin. If it does, run
`/reload-plugins` or start a new session and the plugin appears; if it does
not, the update itself failed and the app log is the place to look. See
[[huit-plugins-installed-locally]] for why only pushed commits install here.
