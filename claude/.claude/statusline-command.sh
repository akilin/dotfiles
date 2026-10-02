#!/bin/bash
# Claude Code status line
# Left (left-aligned):  current context token usage, e.g. 850, 1k, 2.3k
# Right (right-aligned): model display name, effort level (if any),
#                         4 spaces, then 5h / weekly rate-limit usage (if available)
# Spaces in between pad out to the terminal width.

input=$(cat)

# ---- left: token usage ----
# total_input_tokens = tokens currently sitting in the context window
tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')

# round to the nearest 100 (one decimal in k); this is both shown and used for color
rounded=$tokens
[ "$tokens" -ge 1000 ] && rounded=$(( (tokens + 50) / 100 * 100 ))

fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n < 1000) { printf "%d", n; exit }
    r = n / 1000
    if (r == int(r)) printf "%dk", r
    else printf "%.1fk", r
  }'
}
left="$(fmt_tokens "$rounded")"

# colors from Claude Code's dark theme: warning (same as "auto mode on") and error
YELLOW=$'\033[38;2;255;193;7m'
RED=$'\033[38;2;255;107;128m'
RESET=$'\033[0m'

tok_color=$YELLOW
[ "$rounded" -ge 150000 ] && tok_color=$RED
left_c="${tok_color}${left}${RESET}"

# ---- right: model / effort / rate limits ----
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')

right="$model"
[ -n "$effort" ] && right="$right | $effort"

five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# fmt_until RESETS_AT: time left until reset, at most two units, e.g. 1d19h, 2h33m, 15m45s, 45s
# accepts epoch seconds or an ISO-8601 timestamp
fmt_until() {
  [ -z "$1" ] && return
  local target left d h m s
  if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    target=${1%.*}
  else
    target=$(date -d "$1" +%s 2>/dev/null) || return
  fi
  left=$((target - $(date +%s)))
  [ "$left" -lt 0 ] && left=0
  d=$((left / 86400)) h=$((left % 86400 / 3600)) m=$((left % 3600 / 60)) s=$((left % 60))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm%ds' "$m" "$s"
  else printf '%ds' "$s"
  fi
}

# add_limit PCT RESETS_AT: append to limits (plain) and limits_c (red at 90% or more);
# at 90% or more also shows time until reset
limits=""
limits_c=""
add_limit() {
  [ -z "$1" ] && return
  local pct lim lim_c until
  pct=$(printf '%.0f' "$1")
  lim="${pct}%"
  lim_c=$lim
  if [ "$pct" -ge 90 ]; then
    until=$(fmt_until "$2")
    [ -n "$until" ] && lim="$lim ($until)"
    lim_c="${RED}${lim}${RESET}"
  fi
  limits="${limits:+$limits | }$lim"
  limits_c="${limits_c:+$limits_c | }$lim_c"
}
add_limit "$five" "$five_reset"
add_limit "$week" "$week_reset"

right_c=$right
if [ -n "$limits" ]; then
  right="$right    $limits"
  right_c="$right_c    $limits_c"
fi

# ---- terminal width & padding (plain-text lengths, no ANSI here) ----
cols=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
[ -z "$cols" ] && cols="${COLUMNS:-80}"
width=$((cols - 4))
[ "$width" -lt 10 ] && width=10

left_len=${#left}
right_len=${#right}
pad=$((width - left_len - right_len))
[ "$pad" -lt 1 ] && pad=1

printf '%s%*s%s\n' "$left_c" "$pad" "" "$right_c"
