# agent-bar

A multi-service status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows real-time context usage, rate limits, cost tracking, and OAuth status — with built-in support for Claude Code and OpenAI Codex.

```
Opus 4.6  projects/factory  main  +37 -12
context  ======----  62%  2Min/428kout  $4.98 ($3.53/hr)  84m33s  cache:80%  cpu:38% mem:4%
claude   =======--- 75%/day 3M/10M ~10h37m | =========- 95%/wk 3M/50M ~2d10h | ~$4.43
codex    ========-- 84%/5h ~4h 1m          | ===------- 37%/wk ~2d 22h       | ~$0.55
auth     claude:5h48m | codex:6d0h
```

## Features

### Line 1 — Session Header

| Element | Description |
|---------|-------------|
| **Model** | Active model name (e.g., `Opus 4.6`) |
| **Directory** | Last two segments of working directory |
| **Git branch** | Current branch name |
| **Lines changed** | `+added` / `-removed` in this session |

### Line 2 — Context Window

| Element | Description |
|---------|-------------|
| **Progress bar** | Visual fill of the context window |
| **Percentage** | How full the context window is |
| **Tokens** | Cumulative input/output tokens this session |
| **Cost** | Combined session cost (Claude + Codex) in USD |
| **Burn rate** | Projected cost per hour based on session pace |
| **Cache hit %** | Prompt cache efficiency (`cache_read / (cache_read + cache_creation)`) |
| **CPU / Memory** | Claude process resource usage |

### Line 3 — Claude Code Rate Limits

| Element | Description |
|---------|-------------|
| **Daily bar** | Estimated % of daily token budget remaining |
| **Weekly bar** | Estimated % of weekly token budget remaining |
| **Token counts** | Used / limit (e.g., `3M/10M`) |
| **Reset countdown** | Time until the window resets (midnight for daily, Monday for weekly) |
| **Cost** | Claude-only session cost |

Usage is self-tracked across sessions in `~/.claude/agent-bar-usage.json`. Limits are configurable — see [Configuration](#configuration).

> **Note:** Anthropic does not publish exact token limits for Max plans. The defaults (10M/day, 50M/week) are estimates for Max 20x. Adjust to match your experience.

### Line 4 — Codex Rate Limits

| Element | Description |
|---------|-------------|
| **5h bar** | % remaining in the rolling 5-hour window |
| **Weekly bar** | % remaining of weekly quota |
| **Reset countdowns** | Time until each window resets |
| **Estimated cost** | API-equivalent cost based on session tokens |

Rate limit data is read directly from Codex session files in `~/.codex/sessions/`.

> This line only appears if the `codex` CLI is installed and has session data.

### Line 5 — OAuth Status

| Element | Description |
|---------|-------------|
| **claude** | Time until Claude Code OAuth token expires |
| **codex** | Time until Codex OAuth token expires (decoded from JWT) |

## Color System

### Progress Bars

Bars use `=` for filled and `-` for empty, colored by threshold:

**Context window** (higher = worse):
| Color | Threshold | Meaning |
|-------|-----------|---------|
| Green | < 70% | Healthy |
| Yellow | 70-89% | Warning |
| Red | 90%+ | Critical — compaction imminent |

> When the context window fills up, Claude Code automatically compresses earlier messages to free space. The red zone warns you to wrap up complex reasoning before this happens.

**Rate limits** (higher = better):
| Color | Threshold | Meaning |
|-------|-----------|---------|
| Green | > 30% | Healthy |
| Yellow | 10-30% | Running low |
| Red | < 10% | Nearly exhausted |

### OAuth Countdowns

| Color | Threshold | Meaning |
|-------|-----------|---------|
| Green | > 24h | No action needed |
| Yellow | < 24h | Re-auth soon |
| Red | Expired | Re-authenticate now |

### Text Hierarchy

- **Bold + color** — primary data (percentages, model name)
- **Light gray** — secondary metrics (tokens, costs, times)
- **Dark gray** — decorative elements (bar empties, separators)

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (any plan)
- [`jq`](https://jqlang.github.io/jq/) — JSON processing
- `git` — for branch detection
- **Optional:** [Codex CLI](https://github.com/openai/codex) — for Codex rate limit tracking

## Installation

```bash
git clone https://github.com/strataga/agent-bar.git
cd agent-bar
./scripts/install.sh
```

The installer:
1. Copies `statusline.sh` to `~/.claude/statusline.sh`
2. Adds the `statusLine` config to `~/.claude/settings.json`

After installing, restart Claude Code to activate.

### Manual Installation

```bash
cp scripts/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2
  }
}
```

### As a Claude Code Plugin

```bash
claude plugin install /path/to/agent-bar
```

This registers agent-bar as a Claude Code plugin.

## Configuration

Create `~/.claude/agent-bar.json` to override defaults:

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
    "codex": false,
    "auth": true
  }
}
```

Only include the keys you want to override. Unset keys use built-in defaults (10M daily, 50M weekly, bar width 10, all sections enabled).

### Suggested limits by plan

| Plan | Daily Limit | Weekly Limit |
|------|-------------|--------------|
| Claude Pro | `2000000` | `10000000` |
| Claude Max 5x | `5000000` | `25000000` |
| Claude Max 20x | `10000000` | `50000000` |

These are estimates. Adjust based on your actual usage patterns.

## How It Works

### Data Sources

| Data | Source |
|------|--------|
| Session tokens, cost, context % | Claude Code status line JSON (piped to stdin) |
| Claude OAuth expiry | `~/.claude/.credentials.json` |
| Claude daily/weekly usage | Self-tracked in `~/.claude/agent-bar-usage.json` |
| Codex rate limits | `~/.codex/sessions/` (latest session's `token_count` event) |
| Codex OAuth expiry | `~/.codex/auth.json` (JWT `exp` claim) |
| Codex session tokens | `~/.codex/sessions/` (cumulative input/output tokens) |
| Git branch | `git branch --show-current` |
| CPU / Memory | `ps aux` (Claude process) |

### Claude Code Status Line JSON

Claude Code pipes a JSON object to the status line script's stdin on every update:

```json
{
  "model": { "display_name": "Opus 4.6" },
  "workspace": { "current_dir": "/path/to/project" },
  "cost": {
    "total_cost_usd": 4.977,
    "total_duration_ms": 5073000,
    "total_api_duration_ms": 2100000,
    "total_lines_added": 37,
    "total_lines_removed": 12
  },
  "context_window": {
    "used_percentage": 62,
    "remaining_percentage": 38,
    "total_input_tokens": 2152400,
    "total_output_tokens": 428300,
    "cache_creation_input_tokens": 50000,
    "cache_read_input_tokens": 200000
  }
}
```

## Troubleshooting

**Status bar not showing:**
- Verify the script is executable: `chmod +x ~/.claude/statusline.sh`
- Check `~/.claude/settings.json` has the `statusLine` config
- Restart Claude Code

**Empty bars / missing data:**
- First run may show `0%` for daily/weekly until tokens accumulate
- Codex bars only appear when `codex` is installed and has session data

**Codex line not appearing:**
- Requires the `codex` CLI to be installed and in your PATH
- Run a Codex session first to generate session data in `~/.codex/sessions/`

**Wrong daily/weekly limits:**
- Set `claude_daily_limit` and `claude_weekly_limit` in `~/.claude/agent-bar.json`
- Anthropic doesn't publish exact limits; tune based on when you actually get rate-limited

## License

MIT
