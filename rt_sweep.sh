#!/bin/bash
# Red-team sweep (Case Study 2, extra credit #5). READ-ONLY.
# Tries the shared student-admin default key against each group's assigned SSH
# port and reports which groups are OPEN (did not replace the default key).
# Posts a summary to Discord. Runs `hostname` only — NO changes to any machine.
#
# RULES enforced/observed:
#   * Only runs inside the sanctioned window (noon 2026-09-29 -> noon 2026-10-01).
#   * hostname only; never modifies a target. Throttled to avoid WPI IP bans.
#   * If you access an open team, tell them (manual courtesy — not automated).
set -uo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=${MACHINE:-paffenroth-23.dyn.wpi.edu}
BASE_PORT=${BASE_PORT:-22000}
# Only teams that actually have members (empty teams have no VM to attack).
TARGETS=${TARGETS:-"25 20 19 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1"}
MYGROUP=${MYGROUP:-10}                       # skip our own VM
KEY=${KEY:-$BASE/keys/student-admin_key}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-10}           # throttle: don't look like a scanner
WEBHOOK=${DISCORD_WEBHOOK_URL:-$(grep -o 'https://discord.com/api/webhooks/[^ ]*' "$BASE/app.env" 2>/dev/null || true)}

# --- hard window guard (sanctioned red-team period only) ---
NOW=$(date +%s)
START=$(date -d '2026-09-29 12:00:00' +%s 2>/dev/null || echo 0)
END=$(date -d '2026-10-01 12:00:00' +%s 2>/dev/null || echo 0)
if [ "$START" -eq 0 ] || [ "$NOW" -lt "$START" ] || [ "$NOW" -ge "$END" ]; then
  echo "$(date '+%F %T') outside sanctioned red-team window — not running."
  exit 0
fi

post() {  # JSON-safe Discord post
  [ -n "${WEBHOOK:-}" ] || return 0
  curl -s -o /dev/null -H 'Content-Type: application/json' \
    --data "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps({"content":sys.stdin.read()[:1990]}))')" \
    "$WEBHOOK" || true
}

ts="$(date '+%F %H:%M %Z')"
open_list=""
for g in $TARGETS; do
  [ "$g" = "$MYGROUP" ] && continue
  port=$((BASE_PORT + g))
  if host=$(ssh -i "$KEY" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 \
              student-admin@"$MACHINE" hostname 2>/dev/null); then
    open_list+="- group ${g} (port ${port}) OPEN -> ${host}"$'\n'
  fi
  sleep "$SLEEP_BETWEEN"
done

if [ -n "$open_list" ]; then
  msg="🔓 **Red-team sweep ${ts}** — OPEN teams (default key still works):"$'\n'"${open_list}"$'\n'"(read-only hostname check from linux.wpi.edu; notify any team you access)"
else
  msg="🔒 Red-team sweep ${ts} — no open teams found (all locked down)."
fi
echo "$msg"
post "$msg"
