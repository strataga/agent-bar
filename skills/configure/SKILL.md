---
name: agent-bar-configure
description: Configure agent-bar status line settings. Use when user asks to customize the status bar, change limits, enable/disable sections, or adjust the agent-bar display.
tools: Read, Edit, Bash
---

# Agent Bar Configuration

Help the user configure their agent-bar status line.

## Configuration File

Settings are loaded from `~/.claude/agent-bar.json` (user overrides) with fallbacks to `defaults.json` in the plugin directory.

Example `~/.claude/agent-bar.json`:

```json
{
  "claude_daily_limit": 10000000,
  "claude_weekly_limit": 50000000,
  "codex_input_rate": 0.0000025,
  "codex_output_rate": 0.000010,
  "bar_width": 10,
  "sections": {
    "header": true,
    "context": true,
    "claude": true,
    "codex": true,
    "auth": true
  }
}
```

## Settings

The status line is registered in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2
  }
}
```

## Sections

The status bar has 5 lines. Disable any section by setting it to `false` in `~/.claude/agent-bar.json`:

| Line | Label | Content |
|------|-------|---------|
| 1 | Header | Model name, directory, git branch, lines changed |
| 2 | context | Context window bar, tokens, cost, burn rate, cache hit %, CPU/mem |
| 3 | claude | Daily + weekly usage bars with limits and reset countdowns |
| 4 | codex | 5h + weekly rate limit bars with reset countdowns and estimated cost |
| 5 | auth | OAuth token expiry countdowns for both services |

## Common Tasks

- **Change Claude plan limits**: Set `claude_daily_limit` and `claude_weekly_limit`
- **Disable Codex section**: Set `sections.codex` to `false` (users without Codex CLI)
- **Disable auth line**: Set `sections.auth` to `false`
- **Change bar width**: Set `bar_width` (default: 10 characters)
