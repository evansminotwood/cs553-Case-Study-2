#!/bin/bash
# One-time setup of the auto-recovery cron on an always-on WPI host
# (e.g. linux.wpi.edu). Deliverable 3b. Run this ON linux.wpi.edu from inside
# the repo clone, AFTER copying the private keys + app.env from your laptop.
#
# From your LAPTOP first:
#   ssh <you>@linux.wpi.edu 'git clone --branch case_study_2 \
#       https://github.com/evansminotwood/cs553-Case-Study-2.git ~/cs2 && mkdir -p ~/cs2/keys'
#   scp ~/.ssh/cs553_group        <you>@linux.wpi.edu:~/cs2/keys/
#   scp ~/.ssh/student-admin_key  <you>@linux.wpi.edu:~/cs2/keys/
#   scp app.env                   <you>@linux.wpi.edu:~/cs2/
# Then on linux.wpi.edu:
#   cd ~/cs2 && bash setup_recovery.sh
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
REPO_URL=${REPO_URL:-https://github.com/evansminotwood/cs553-Case-Study-2.git}
CRON_MIN=${CRON_MIN:-5}

# 1. verify required secrets are present
for f in keys/cs553_group keys/student-admin_key app.env; do
  [ -f "$BASE/$f" ] || { echo "Missing $BASE/$f — scp it from your laptop first. Aborting."; exit 1; }
done
grep -q '^DISCORD_WEBHOOK_URL=' "$BASE/app.env" || { echo "app.env has no DISCORD_WEBHOOK_URL. Aborting."; exit 1; }

# derive the public key (deploy.sh needs cs553_group.pub) and fix permissions
[ -f "$BASE/keys/cs553_group.pub" ] || ssh-keygen -y -f "$BASE/keys/cs553_group" > "$BASE/keys/cs553_group.pub"
chmod 700 "$BASE/keys"; chmod 600 "$BASE"/keys/cs553_group "$BASE"/keys/student-admin_key "$BASE/app.env"

# 2. sanity: can we reach the VM with the team key?
if ssh -i "$BASE/keys/cs553_group" -p 22010 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 student-admin@paffenroth-23.dyn.wpi.edu true 2>/dev/null; then
  echo "[setup] reached the VM with the team key"
else
  echo "[setup] WARNING: could not reach the VM right now (down/wiped?) — recovery will handle it on its next run"
fi

# 3. install/refresh the crontab entry (idempotent: replaces any prior line).
# `crontab -l` errors when no crontab exists yet; `|| true` keeps set -e happy.
LINE="*/${CRON_MIN} * * * * REPO_URL=${REPO_URL} BASE=${BASE} ${BASE}/recovery.sh"
{ (crontab -l 2>/dev/null | grep -vF "${BASE}/recovery.sh") || true; echo "$LINE"; } | crontab -
echo "[setup] cron installed:"; crontab -l | grep -F "${BASE}/recovery.sh"

# 4. run recovery once now to seed the log
(cd "$BASE" && BASE="$BASE" MYKEY="$BASE/keys/cs553_group" DEFAULT_KEY="$BASE/keys/student-admin_key" REPO_URL="$REPO_URL" ./recovery.sh) || true
echo "[setup] done. Watch: tail -f $BASE/recovery.log"
tail -n 5 "$BASE/recovery.log" 2>/dev/null || true
