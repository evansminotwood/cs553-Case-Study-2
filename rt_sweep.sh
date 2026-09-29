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
VM_IP=${VM_IP:-130.215.182.120}   # DNS-proof fallback if this node can't resolve the name
getent hosts "$MACHINE" >/dev/null 2>&1 || MACHINE="$VM_IP"
BASE_PORT=${BASE_PORT:-22000}
# Only teams that actually have members (empty teams have no VM to attack).
TARGETS=${TARGETS:-"25 20 19 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1"}
MYGROUP=${MYGROUP:-10}                       # skip our own VM
KEY=${KEY:-$BASE/keys/student-admin_key}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-10}           # throttle: don't look like a scanner
WEBHOOK=${DISCORD_WEBHOOK_URL:-$(grep -o 'https://discord.com/api/webhooks/[^ ]*' "$BASE/app.env" 2>/dev/null || true)}

# SELFTEST=1 verifies the probe + Discord pipeline against OUR OWN VM only
# (authorized any time); it bypasses the window guard and targets nobody else.
if [ "${SELFTEST:-0}" = "1" ]; then
  echo "[selftest] probing only our own VM (group ${MYGROUP}); window guard bypassed"
  TARGETS="$MYGROUP"; MYGROUP="__selftest_none__"
else
  # --- hard window guard (sanctioned red-team period only) ---
  NOW=$(date +%s)
  START=$(date -d '2026-09-29 12:00:00' +%s 2>/dev/null || echo 0)
  END=$(date -d '2026-10-01 12:00:00' +%s 2>/dev/null || echo 0)
  if [ "$START" -eq 0 ] || [ "$NOW" -lt "$START" ] || [ "$NOW" -ge "$END" ]; then
    echo "$(date '+%F %T') outside sanctioned red-team window — not running."
    exit 0
  fi
fi

post() {  # JSON-safe Discord post
  [ -n "${WEBHOOK:-}" ] || return 0
  curl -s -o /dev/null -H 'Content-Type: application/json' \
    --data "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps({"content":sys.stdin.read()[:1990]}))')" \
    "$WEBHOOK" || true
}

ts="$(date '+%F %H:%M %Z')"
rows=""; open_count=0; total=0
for g in $TARGETS; do
  [ "$g" = "$MYGROUP" ] && continue
  total=$((total+1)); port=$((BASE_PORT + g))
  if host=$(ssh -i "$KEY" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 \
              student-admin@"$MACHINE" hostname 2>/dev/null); then
    rows+="$(printf '%-6s %-7s OPEN (%s)' "$g" "$port" "$host")"$'\n'; open_count=$((open_count+1))
  else
    rows+="$(printf '%-6s %-7s protected' "$g" "$port")"$'\n'
  fi
  sleep "$SLEEP_BETWEEN"
done

hdr="$(printf '%-6s %-7s %s' group port status)"
msg="**Red-team sweep ${ts}** — ${open_count}/${total} OPEN (read-only hostname check; notify any team you access)"$'\n'"\`\`\`"$'\n'"${hdr}"$'\n'"------------------------------"$'\n'"${rows}\`\`\`"
echo "$msg"
post "$msg"
