---
name: agent-bar-setup
description: Install and activate the agent-bar status line. Use when user says "set up agent-bar", "install agent-bar", "activate agent-bar", or "configure statusline".
tools: Bash, Read
---

# Agent Bar Setup

Install and activate the agent-bar status line for Claude Code.

## Steps

1. Run the install script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh"
```

2. After the script completes, tell the user:
   - The statusline script has been installed to `~/.claude/statusline.sh`
   - The `statusLine` config has been added to `~/.claude/settings.json`
   - They need to **restart Claude Code** for the status bar to appear

3. Mention that they can customize settings by creating `~/.claude/agent-bar.json` — or by running `/agent-bar:configure`.

## Troubleshooting

If `jq` is not installed, tell the user to install it first:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt install jq`
- Other: https://jqlang.github.io/jq/download/
