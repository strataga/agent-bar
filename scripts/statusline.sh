#!/bin/bash
input=$(cat)

# --- Paths ---
CLAUDE_CREDS="$HOME/.claude/.credentials.json"
CODEX_DIR="$HOME/.codex"
CODEX_AUTH_FILE="$CODEX_DIR/auth.json"
CODEX_SESSIONS_DIR="$CODEX_DIR/sessions"
USAGE_LOG="$HOME/.claude/agent-bar-usage.json"
SETTINGS="$HOME/.claude/agent-bar.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS="$SCRIPT_DIR/defaults.json"

# --- Load settings (user overrides > defaults) ---
cfg() {
  local val=""
  [ -f "$SETTINGS" ] && val=$(jq -r "$1 // empty" "$SETTINGS" 2>/dev/null)
  [ -z "$val" ] && [ -f "$DEFAULTS" ] && val=$(jq -r "$1 // empty" "$DEFAULTS" 2>/dev/null)
  echo "${val:-$2}"
}

CLAUDE_DAILY_LIMIT=$(cfg '.claude_daily_limit' '10000000')
CLAUDE_WEEKLY_LIMIT=$(cfg '.claude_weekly_limit' '50000000')
CODEX_INPUT_RATE=$(cfg '.codex_input_rate' '0.0000025')
CODEX_OUTPUT_RATE=$(cfg '.codex_output_rate' '0.000010')
BAR_WIDTH=$(cfg '.bar_width' '10')

SEC_HEADER=$(cfg '.sections.header' 'true')
SEC_CONTEXT=$(cfg '.sections.context' 'true')
SEC_CLAUDE=$(cfg '.sections.claude' 'true')
SEC_CODEX=$(cfg '.sections.codex' 'true')
SEC_AUTH=$(cfg '.sections.auth' 'true')

# --- Extract session data ---
MODEL=$(echo "$input" | jq -r '.model.display_name // "—"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "—"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
IN_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOK=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
LINES_ADD=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_DEL=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.cache_creation_input_tokens // 0')
CACHE_READ=$(echo "$input" | jq -r '.context_window.cache_read_input_tokens // 0')

# ═══════════════════════════════════════════════
# ANSI colors
# ═══════════════════════════════════════════════
C='\033[36m'    # cyan
G='\033[32m'    # green
Y='\033[33m'    # yellow
R='\033[31m'    # red
D='\033[37m'    # secondary text (light gray)
DM='\033[90m'   # dim (dark gray — bar empties, faint accents)
B='\033[1m'     # bold
M='\033[35m'    # magenta
X='\033[0m'     # reset

# Separator between metric groups (3 visible chars: space, pipe, space)
S=" ${DM}|${X} "

# Labels — left-aligned, padded to 8 visible chars so bars/content start at same column
LBL_CTX="${M}context${X} "
LBL_CL="${M}claude${X}  "
LBL_CX="${M}codex${X}   "
LBL_AU="${M}auth${X}    "

# ═══════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════
make_bar() {
  local pct=$1 width=${2:-10} color="${3}"
  [ "$pct" -gt 100 ] && pct=100
  [ "$pct" -lt 0 ] && pct=0
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  [ "$filled" -gt 0 ] && bar="${color}$(printf "%${filled}s" | tr ' ' '=')"
  [ "$empty" -gt 0 ] && bar+="\\033[90m$(printf "%${empty}s" | tr ' ' '-')"
  bar+="\\033[0m"
  printf '%s' "$bar"
}

pct_color_remaining() {
  local pct=$1
  if [ "$pct" -le 10 ]; then echo "$R"
  elif [ "$pct" -le 30 ]; then echo "$Y"
  else echo "$G"; fi
}

pct_color_used() {
  local pct=$1
  if [ "$pct" -ge 90 ]; then echo "$R"
  elif [ "$pct" -ge 70 ]; then echo "$Y"
  else echo "$G"; fi
}

fmt_k() {
  if [ "$1" -ge 1000000 ]; then echo "$(( ($1 + 500000) / 1000000 ))M"
  elif [ "$1" -ge 1000 ]; then echo "$(( ($1 + 500) / 1000 ))k"
  else echo "$1"; fi
}

oauth_countdown() {
  local expires_ms=$1
  local now_ms=$(( $(date +%s) * 1000 ))
  local left_ms=$(( expires_ms - now_ms ))
  if [ "$left_ms" -le 0 ]; then echo "EXPIRED"; return; fi
  local left_s=$(( left_ms / 1000 ))
  local days=$(( left_s / 86400 ))
  local hrs=$(( (left_s % 86400) / 3600 ))
  local mins=$(( (left_s % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then echo "${days}d${hrs}h"
  elif [ "$hrs" -gt 0 ]; then echo "${hrs}h${mins}m"
  else echo "${mins}m"; fi
}

oauth_color() {
  local expires_ms=$1
  local now_ms=$(( $(date +%s) * 1000 ))
  local left_h=$(( (expires_ms - now_ms) / 3600000 ))
  if [ "$left_h" -le 0 ]; then echo "$R"
  elif [ "$left_h" -le 24 ]; then echo "$Y"
  else echo "$G"; fi
}

# ═══════════════════════════════════════════════
# Data collection
# ═══════════════════════════════════════════════

IN_FMT=$(fmt_k "$IN_TOK")
OUT_FMT=$(fmt_k "$OUT_TOK")
MINS=$((DURATION_MS / 60000))
SECS=$(((DURATION_MS % 60000) / 1000))

# Git branch
BRANCH=""
git rev-parse --git-dir &>/dev/null && BRANCH=$(git branch --show-current 2>/dev/null)

# System stats
STATS=$(ps aux | grep -i "[C]laude" | head -1 | awk '{printf "%.0f%% %.0f%%", $3, $4}')
CPU=$(echo "$STATS" | cut -d'%' -f1)
MEM=$(echo "$STATS" | cut -d' ' -f2 | cut -d'%' -f1)

# Short dir
SHORT_DIR=$(echo "$DIR" | rev | cut -d'/' -f1-2 | rev)

# Cache hit ratio
CACHE_TOTAL=$(( CACHE_CREATE + CACHE_READ ))
CACHE_HIT=""
[ "$CACHE_TOTAL" -gt 0 ] && CACHE_HIT=$(( CACHE_READ * 100 / CACHE_TOTAL ))

# Burn rate (recomputed after combined cost below)
BURN=""

# --- Claude OAuth ---
CLAUDE_TTL=""
CLAUDE_TTL_C="$G"
if [ -f "$CLAUDE_CREDS" ]; then
  CLAUDE_EXP=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CLAUDE_CREDS" 2>/dev/null)
  if [ "$CLAUDE_EXP" -gt 0 ] 2>/dev/null; then
    CLAUDE_TTL=$(oauth_countdown "$CLAUDE_EXP")
    CLAUDE_TTL_C=$(oauth_color "$CLAUDE_EXP")
  fi
fi

# --- Codex data (read from ~/.codex session files) ---
CODEX_TTL=""
CODEX_TTL_C="$G"
CODEX_PRIMARY_REM=""
CODEX_SECONDARY_REM=""
CODEX_P_RESET=""
CODEX_S_RESET=""
CODEX_PRIMARY_C="$G"
CODEX_SECONDARY_C="$G"
CODEX_COST=""

if command -v codex &>/dev/null && [ -d "$CODEX_SESSIONS_DIR" ]; then
  # Find latest session file
  CODEX_LATEST=$(find "$CODEX_SESSIONS_DIR" -name '*.jsonl' -type f 2>/dev/null | sort | tail -1)

  if [ -n "$CODEX_LATEST" ]; then
    # Get last token_count event from session
    CODEX_DATA=$(grep '"token_count"' "$CODEX_LATEST" 2>/dev/null | tail -1)

    if [ -n "$CODEX_DATA" ]; then
      # Rate limits — primary (5h window) and secondary (weekly)
      CX_P_USED=$(echo "$CODEX_DATA" | jq -r '.payload.rate_limits.primary.used_percent // empty' 2>/dev/null | cut -d. -f1)
      CX_S_USED=$(echo "$CODEX_DATA" | jq -r '.payload.rate_limits.secondary.used_percent // empty' 2>/dev/null | cut -d. -f1)
      CX_P_RESETS=$(echo "$CODEX_DATA" | jq -r '.payload.rate_limits.primary.resets_at // empty' 2>/dev/null)
      CX_S_RESETS=$(echo "$CODEX_DATA" | jq -r '.payload.rate_limits.secondary.resets_at // empty' 2>/dev/null)

      if [ -n "$CX_P_USED" ]; then
        CODEX_PRIMARY_REM=$(( 100 - CX_P_USED ))
        [ "$CODEX_PRIMARY_REM" -lt 0 ] && CODEX_PRIMARY_REM=0
        CODEX_PRIMARY_C=$(pct_color_remaining "$CODEX_PRIMARY_REM")
      fi
      if [ -n "$CX_S_USED" ]; then
        CODEX_SECONDARY_REM=$(( 100 - CX_S_USED ))
        [ "$CODEX_SECONDARY_REM" -lt 0 ] && CODEX_SECONDARY_REM=0
        CODEX_SECONDARY_C=$(pct_color_remaining "$CODEX_SECONDARY_REM")
      fi

      # Reset countdowns from epoch seconds
      if [ -n "$CX_P_RESETS" ]; then
        CX_P_LEFT=$(( CX_P_RESETS - $(date +%s) ))
        [ "$CX_P_LEFT" -gt 0 ] && CODEX_P_RESET="$(( CX_P_LEFT / 3600 ))h$(( (CX_P_LEFT % 3600) / 60 ))m"
      fi
      if [ -n "$CX_S_RESETS" ]; then
        CX_S_LEFT=$(( CX_S_RESETS - $(date +%s) ))
        if [ "$CX_S_LEFT" -gt 0 ]; then
          CX_S_DAYS=$(( CX_S_LEFT / 86400 ))
          CX_S_HRS=$(( (CX_S_LEFT % 86400) / 3600 ))
          if [ "$CX_S_DAYS" -gt 0 ]; then
            CODEX_S_RESET="${CX_S_DAYS}d ${CX_S_HRS}h"
          else
            CODEX_S_RESET="${CX_S_HRS}h$(( (CX_S_LEFT % 3600) / 60 ))m"
          fi
        fi
      fi

      # Token counts for cost estimation
      CX_IN=$(echo "$CODEX_DATA" | jq -r '.payload.info.total_token_usage.input_tokens // 0' 2>/dev/null)
      CX_OUT=$(echo "$CODEX_DATA" | jq -r '.payload.info.total_token_usage.output_tokens // 0' 2>/dev/null)
      if [ "${CX_IN:-0}" -gt 0 ] || [ "${CX_OUT:-0}" -gt 0 ]; then
        CODEX_COST=$(awk "BEGIN {printf \"%.2f\", (${CX_IN:-0} * $CODEX_INPUT_RATE) + (${CX_OUT:-0} * $CODEX_OUTPUT_RATE)}")
      fi
    fi
  fi

  # Codex OAuth — decode JWT expiry from access token
  if [ -f "$CODEX_AUTH_FILE" ]; then
    CX_TOKEN=$(jq -r '.tokens.access_token // empty' "$CODEX_AUTH_FILE" 2>/dev/null)
    if [ -n "$CX_TOKEN" ]; then
      # JWT uses base64url — convert to standard base64 and add padding
      CX_PAYLOAD=$(echo "$CX_TOKEN" | cut -d. -f2 | tr '_-' '/+')
      case $(( ${#CX_PAYLOAD} % 4 )) in
        2) CX_PAYLOAD+="==" ;; 3) CX_PAYLOAD+="=" ;;
      esac
      CX_EXP_S=$(echo "$CX_PAYLOAD" | base64 -d 2>/dev/null | jq -r '.exp // 0' 2>/dev/null)
      if [ "${CX_EXP_S:-0}" -gt 0 ] 2>/dev/null; then
        CX_EXP_MS=$(( CX_EXP_S * 1000 ))
        CODEX_TTL=$(oauth_countdown "$CX_EXP_MS")
        CODEX_TTL_C=$(oauth_color "$CX_EXP_MS")
      fi
    fi
  fi
fi

# --- Combined cost (Claude + Codex) ---
TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $COST + ${CODEX_COST:-0}}")
[ "$DURATION_MS" -gt 60000 ] && BURN=$(awk "BEGIN {printf \"%.2f\", $TOTAL_COST / ($DURATION_MS / 3600000)}")

# ═══════════════════════════════════════════════
# Claude daily + weekly tracking
# ═══════════════════════════════════════════════
TODAY=$(date +%Y-%m-%d)
WEEK_START=$(date -v-monday +%Y-%m-%d 2>/dev/null || date -d "last monday" +%Y-%m-%d 2>/dev/null || echo "$TODAY")
TOTAL_TOK=$(( IN_TOK + OUT_TOK ))

CLAUDE_DAY_PREV=0
CLAUDE_WEEK_PREV=0
if [ -f "$USAGE_LOG" ]; then
  [ "$(jq -r '.claude_daily.date // ""' "$USAGE_LOG" 2>/dev/null)" = "$TODAY" ] && \
    CLAUDE_DAY_PREV=$(jq -r '.claude_daily.tokens // 0' "$USAGE_LOG" 2>/dev/null)
  [ "$(jq -r '.claude_weekly.week_start // ""' "$USAGE_LOG" 2>/dev/null)" = "$WEEK_START" ] && \
    CLAUDE_WEEK_PREV=$(jq -r '.claude_weekly.tokens // 0' "$USAGE_LOG" 2>/dev/null)
fi

CLAUDE_DAY_TOK=$(( CLAUDE_DAY_PREV > TOTAL_TOK ? CLAUDE_DAY_PREV : TOTAL_TOK ))
CLAUDE_WEEK_TOK=$(( CLAUDE_WEEK_PREV > TOTAL_TOK ? CLAUDE_WEEK_PREV : TOTAL_TOK ))

echo "{\"claude_daily\":{\"date\":\"$TODAY\",\"tokens\":$CLAUDE_DAY_TOK},\"claude_weekly\":{\"week_start\":\"$WEEK_START\",\"tokens\":$CLAUDE_WEEK_TOK},\"updated\":\"$(date -u +%H:%M:%S)\"}" > "$USAGE_LOG"

CLAUDE_DAY_PCT=$(( CLAUDE_DAY_TOK * 100 / CLAUDE_DAILY_LIMIT ))
CLAUDE_WEEK_PCT=$(( CLAUDE_WEEK_TOK * 100 / CLAUDE_WEEKLY_LIMIT ))
[ "$CLAUDE_DAY_PCT" -gt 100 ] && CLAUDE_DAY_PCT=100
[ "$CLAUDE_WEEK_PCT" -gt 100 ] && CLAUDE_WEEK_PCT=100
CLAUDE_DAY_REM=$(( 100 - CLAUDE_DAY_PCT ))
CLAUDE_WEEK_REM=$(( 100 - CLAUDE_WEEK_PCT ))

# Reset countdowns
NOW_EPOCH=$(date +%s)
SEC_TODAY=$(( NOW_EPOCH - $(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" +%s 2>/dev/null || echo "$NOW_EPOCH") ))
DAY_LEFT_S=$(( 86400 - SEC_TODAY ))
[ "$DAY_LEFT_S" -le 0 ] && DAY_LEFT_S=0
CLAUDE_DAY_RESET="$(( DAY_LEFT_S / 3600 ))h$(( (DAY_LEFT_S % 3600) / 60 ))m"

DOW=$(date +%u)
DAYS_TO_MON=$(( (8 - DOW) % 7 ))
[ "$DAYS_TO_MON" -eq 0 ] && DAYS_TO_MON=7
WEEK_LEFT_S=$(( DAY_LEFT_S + (DAYS_TO_MON - 1) * 86400 ))
CLAUDE_WEEK_RESET="$(( WEEK_LEFT_S / 86400 ))d$(( (WEEK_LEFT_S % 86400) / 3600 ))h"

# ═══════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════

# --- Line 1: header ---
if [ "$SEC_HEADER" = "true" ]; then
  L1="${B}${C}${MODEL}${X}  ${D}${SHORT_DIR}${X}"
  [ -n "$BRANCH" ] && L1+="  ${G}${BRANCH}${X}"
  ([ "$LINES_ADD" -gt 0 ] || [ "$LINES_DEL" -gt 0 ]) && L1+="  ${G}+${LINES_ADD}${X} ${R}-${LINES_DEL}${X}"
  echo -e "$L1"
fi

# --- Line 2: context ---
if [ "$SEC_CONTEXT" = "true" ]; then
  CTX_C=$(pct_color_used "$PCT")
  L2="${LBL_CTX} $(make_bar "$PCT" "$BAR_WIDTH" "$CTX_C") ${CTX_C}${B}$(printf '%4s' "${PCT}%")${X}"
  L2+="  ${D}${IN_FMT}in/${OUT_FMT}out${X}"
  L2+="  ${D}\$${TOTAL_COST}${X}"
  [ -n "$BURN" ] && L2+=" ${D}(\$${BURN}/hr)${X}"
  L2+="  ${D}${MINS}m${SECS}s${X}"
  [ -n "$CACHE_HIT" ] && L2+="  ${D}cache:${CACHE_HIT}%${X}"
  [ -n "$CPU" ] && L2+="  ${D}cpu:${CPU}%${X} ${D}mem:${MEM}%${X}"
  echo -e "$L2"
fi

# --- Line 3: claude rate limits ---
if [ "$SEC_CLAUDE" = "true" ]; then
  CL_D_C=$(pct_color_remaining "$CLAUDE_DAY_REM")
  CL_W_C=$(pct_color_remaining "$CLAUDE_WEEK_REM")
  L3="${LBL_CL} $(make_bar "$CLAUDE_DAY_REM" "$BAR_WIDTH" "$CL_D_C")"
  L3+=" ${CL_D_C}${B}$(printf '%4s' "${CLAUDE_DAY_REM}%")${X}"
  _d="/day $(fmt_k "$CLAUDE_DAY_TOK")/$(fmt_k "$CLAUDE_DAILY_LIMIT") ~${CLAUDE_DAY_RESET}"
  L3+="${D}$(printf '%-21s' "$_d")${X}"
  L3+="${S}$(make_bar "$CLAUDE_WEEK_REM" "$BAR_WIDTH" "$CL_W_C")"
  L3+=" ${CL_W_C}${B}$(printf '%4s' "${CLAUDE_WEEK_REM}%")${X}"
  _d="/wk $(fmt_k "$CLAUDE_WEEK_TOK")/$(fmt_k "$CLAUDE_WEEKLY_LIMIT") ~${CLAUDE_WEEK_RESET}"
  L3+="${D}$(printf '%-21s' "$_d")${X}"
  L3+="${S}${D}~\$$(printf '%.2f' "$COST")${X}"
  echo -e "$L3"
fi

# --- Line 4: codex rate limits ---
if [ "$SEC_CODEX" = "true" ] && [ -n "$CODEX_PRIMARY_REM" ]; then
  L4="${LBL_CX} $(make_bar "$CODEX_PRIMARY_REM" "$BAR_WIDTH" "$CODEX_PRIMARY_C")"
  L4+=" ${CODEX_PRIMARY_C}${B}$(printf '%4s' "${CODEX_PRIMARY_REM}%")${X}"
  _d="/5h ${CODEX_P_RESET:+~$CODEX_P_RESET}"
  L4+="${D}$(printf '%-21s' "$_d")${X}"
  if [ -n "$CODEX_SECONDARY_REM" ]; then
    L4+="${S}$(make_bar "${CODEX_SECONDARY_REM}" "$BAR_WIDTH" "$CODEX_SECONDARY_C")"
    L4+=" ${CODEX_SECONDARY_C}${B}$(printf '%4s' "${CODEX_SECONDARY_REM}%")${X}"
    _d="/wk ${CODEX_S_RESET:+~$CODEX_S_RESET}"
    L4+="${D}$(printf '%-21s' "$_d")${X}"
  fi
  [ -n "$CODEX_COST" ] && L4+="${S}${D}~\$${CODEX_COST}${X}"
  echo -e "$L4"
fi

# --- Line 5: auth ---
if [ "$SEC_AUTH" = "true" ]; then
  L5="${LBL_AU}"
  [ -n "$CLAUDE_TTL" ] && L5+=" ${D}claude:${X}${CLAUDE_TTL_C}${B}${CLAUDE_TTL}${X}"
  if [ -n "$CODEX_TTL" ]; then
    [ -n "$CLAUDE_TTL" ] && L5+="${S}" || L5+=" "
    L5+="${D}codex:${X}${CODEX_TTL_C}${B}${CODEX_TTL}${X}"
  fi
  echo -e "$L5"
fi

wait 2>/dev/null
