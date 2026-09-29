#!/bin/bash
# Install the red-team sweep cron on linux.wpi.edu (extra credit #5).
# Run ON linux.wpi.edu from inside ~/cs2, after keys + app.env are in place.
# Default schedule: noon, 15:00, 18:00, 21:00. Override with SCHED=... .
# rt_sweep.sh self-guards to the sanctioned window, so misfires are harmless.
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
SCHED=${SCHED:-"0 12,15,18,21 * * *"}

[ -f "$BASE/keys/student-admin_key" ] || { echo "Missing keys/student-admin_key. Aborting."; exit 1; }
[ -f "$BASE/app.env" ] || { echo "Missing app.env (webhook). Aborting."; exit 1; }
chmod 600 "$BASE/keys/student-admin_key" "$BASE/app.env"

LINE="${SCHED} BASE=${BASE} ${BASE}/rt_sweep.sh >> ${BASE}/rt_sweep.log 2>&1"
{ (crontab -l 2>/dev/null | grep -vF "${BASE}/rt_sweep.sh") || true; echo "$LINE"; } | crontab -
echo "[setup] red-team sweep cron installed:"; crontab -l | grep -F "${BASE}/rt_sweep.sh"
echo "[setup] first sweep runs at noon. Do NOT run rt_sweep.sh before noon — it self-guards anyway."
