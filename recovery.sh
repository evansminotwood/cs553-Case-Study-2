#!/bin/bash
# Automatic server recovery (Case Study 2, deliverable 3b).
# Runs from cron on an always-on WPI host (e.g. linux.wpi.edu) that can reach
# the VM. Detects the VM's state and self-heals:
#
#   your key + app up      -> healthy, do nothing
#   your key + app down     -> restart the systemd service (redeploy if that fails)
#   only default key works  -> VM was WIPED -> full redeploy + re-lock
#   neither key reachable    -> VM is down/rebooting -> retry next tick
#
# Setup on the recovery host ($BASE):
#   git clone <your repo> $BASE          # provides deploy.sh + effectivechatbot.service
#   cp your keys here: $BASE/keys/cs553_group[.pub], $BASE/keys/student-admin_key  (chmod 600)
#   create $BASE/app.env with DISCORD_WEBHOOK_URL=...   (chmod 600)
#   crontab:  */5 * * * * REPO_URL=<your repo> $BASE/recovery.sh
set -uo pipefail

BASE=${BASE:-$HOME/cs2}
PORT=${PORT:-22010}
MACHINE=${MACHINE:-paffenroth-23.dyn.wpi.edu}
REMOTE="student-admin@${MACHINE}"
LOG=${LOG:-$BASE/recovery.log}
# deploy.sh aborts without a real REPO_URL; default it here so manual runs work
# too (not just cron, which passes it in the crontab line).
REPO_URL=${REPO_URL:-https://github.com/evansminotwood/cs553-Case-Study-2.git}

MYKEY=${MYKEY:-$BASE/keys/cs553_group}
DEFAULT_KEY=${DEFAULT_KEY:-$BASE/keys/student-admin_key}
WEBHOOK=${DISCORD_WEBHOOK_URL:-$(grep -o 'https://discord.com/api/webhooks/[^ ]*' "$BASE/app.env" 2>/dev/null || true)}

say() { echo "$(date '+%F %T') $*" >> "$LOG"; }
# Posts to Discord for action events only (not healthy ticks) to avoid spam.
notify() {
  [ -n "${WEBHOOK:-}" ] || return 0
  curl -s -o /dev/null -H 'Content-Type: application/json' \
    --data "$(printf '%s' "🔁 recovery: $1" | python3 -c 'import json,sys;print(json.dumps({"content":sys.stdin.read()[:1990]}))')" \
    "$WEBHOOK" || true
}
reachable() { ssh -i "$1" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$REMOTE" true 2>/dev/null; }
# Port 7860 is not exposed off the VM (WPI forwards only the SSH port), so check
# the app on the VM's own localhost via SSH rather than the external hostname.
app_up() { ssh -i "$MYKEY" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$REMOTE" 'curl -fsS -o /dev/null --max-time 10 http://localhost:7860' 2>/dev/null; }
# deploy.sh reads the same key/port config from the environment we export below.
redeploy() { (cd "$BASE" && REPO_URL="$REPO_URL" MYKEY="$MYKEY" DEFAULT_KEY="$DEFAULT_KEY" PORT="$PORT" ./deploy.sh >>"$LOG" 2>&1); }

if reachable "$MYKEY"; then
  if app_up; then
    say "OK (your key, app up)"; exit 0
  fi
  say "app DOWN (your key works) -> restart service"
  if ssh -i "$MYKEY" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$REMOTE" "sudo systemctl restart effectivechatbot" 2>>"$LOG"; then
    say "restart issued"; notify "app was down — restart issued on $MACHINE:$PORT"
  else
    say "restart failed -> full redeploy"; notify "app down + restart failed — running full redeploy"
    redeploy && { say "redeploy done"; notify "redeploy done"; } || { say "redeploy FAILED"; notify "redeploy FAILED"; }
  fi
  exit 0
fi

if reachable "$DEFAULT_KEY"; then
  say "WIPED (only default key) -> full redeploy + re-lock"; notify "VM WIPED (only default key) — redeploying + re-locking"
  redeploy && { say "redeploy done"; notify "redeploy done — VM re-locked"; } || { say "redeploy FAILED"; notify "redeploy FAILED"; }
  exit 0
fi

say "VM unreachable with both keys (down/rebooting) -> retry next tick"
exit 0
