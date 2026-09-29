#!/bin/bash
# Automated deployment (Case Study 2, deliverable 3a).
#
# Idempotent and safe to re-run. Works whether the VM is:
#   * freshly wiped  -> only the default student-admin key works, and
#   * already locked  -> your personal key works.
#
# ANTI-LOCKOUT: your key is added and VERIFIED to log in BEFORE the default
# key is removed, so a malformed key can never lock you out.
#
# Requires both keys to exist locally: your personal key (MYKEY, installed as the
# only authorized key) and the default key (DEFAULT_KEY, used only to bootstrap a
# freshly-wiped VM back to a locked-down state).
set -euo pipefail

# ---- config (override via env) ----
PORT=${PORT:-22010}
MACHINE=${MACHINE:-paffenroth-23.dyn.wpi.edu}
MYKEY=${MYKEY:-$HOME/.ssh/cs553_group}
MYPUB=${MYPUB:-${MYKEY}.pub}
DEFAULT_KEY=${DEFAULT_KEY:-$HOME/.ssh/student-admin_key}
TEAM_KEYS=${TEAM_KEYS:-./team_authorized_keys}   # all teammates' PUBLIC keys
REPO_URL=${REPO_URL:-https://github.com/<YOUR_GH_USER>/<YOUR_REPO>.git}
REPO_BRANCH=${REPO_BRANCH:-case_study_2}
APP_DIR=${APP_DIR:-DSCS553_example}
SECRET_ENV=${SECRET_ENV:-./app.env}   # local file with DISCORD_WEBHOOK_URL=...

REMOTE="student-admin@${MACHINE}"
COMMON="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
BATCH="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
REMOTE_APP_DIR="/home/student-admin/${APP_DIR}"

# ---- 0. preflight ----
case "$REPO_URL" in
  *"<YOUR"*) echo "Set REPO_URL to your GitHub repo (env or edit this file). Aborting."; exit 1;;
esac
[ -f "$MYKEY" ] && [ -f "$MYPUB" ] || { echo "Missing MYKEY/$MYPUB. Aborting."; exit 1; }
[ -f "$TEAM_KEYS" ] || { echo "Missing $TEAM_KEYS. Aborting."; exit 1; }
# Anti-lockout: the operator's own key MUST be in the team file we install.
grep -qF "$(awk '{print $2}' "$MYPUB")" "$TEAM_KEYS" || { echo "Your key ($MYPUB) is not in $TEAM_KEYS. Aborting."; exit 1; }
[ -f "$SECRET_ENV" ] || { echo "Missing $SECRET_ENV (needs DISCORD_WEBHOOK_URL=...). Aborting."; exit 1; }
grep -q '^DISCORD_WEBHOOK_URL=' "$SECRET_ENV" || { echo "$SECRET_ENV has no DISCORD_WEBHOOK_URL=. Aborting."; exit 1; }

ssh-keygen -R "[${MACHINE}]:${PORT}" >/dev/null 2>&1 || true   # stale host key across wipes

try_key() { ssh -i "$1" -p "$PORT" $BATCH "$REMOTE" true 2>/dev/null; }

# ---- 1. pick a key that currently works ----
if try_key "$MYKEY"; then
  ACTIVE="$MYKEY"; echo "[deploy] reached VM with your key (already locked down)"
elif [ -f "$DEFAULT_KEY" ] && try_key "$DEFAULT_KEY"; then
  ACTIVE="$DEFAULT_KEY"; echo "[deploy] reached VM with default key (fresh/wiped)"
else
  echo "[deploy] cannot reach VM with either key (down?). Aborting."; exit 1
fi
SSH() { ssh -i "$ACTIVE" -p "$PORT" $COMMON "$REMOTE" "$@"; }
SCP() { scp -i "$ACTIVE" -P "$PORT" $COMMON "$@"; }

# ---- 2. install team keys, VERIFY, then remove default ----
SCP "$TEAM_KEYS" "${REMOTE}:/tmp/team_keys"
SSH 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys &&
     cat /tmp/team_keys >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys;
     chmod 600 ~/.ssh/authorized_keys'
try_key "$MYKEY" || { echo "[deploy] your key failed after add; NOT removing default. Aborting."; exit 1; }
echo "[deploy] your key verified"
# lock down: authorized_keys := ONLY the team keys. The overwrite removes the
# default key, so switch to MYKEY immediately and finish with it (doing chmod via
# the just-removed default key is the bug this ordering fixes).
SCP "$TEAM_KEYS" "${REMOTE}:/home/student-admin/.ssh/authorized_keys"
ACTIVE="$MYKEY"
try_key "$MYKEY" || { echo "[deploy] lockdown verify FAILED (your key not usable). Aborting."; exit 1; }
SSH 'chmod 600 ~/.ssh/authorized_keys; rm -f /tmp/team_keys'
echo "[deploy] locked down to your team's keys only"

# ---- 3. code: clone or fast-forward your repo ----
SSH "if [ -d '${REMOTE_APP_DIR}/.git' ]; then
        cd '${REMOTE_APP_DIR}' && git fetch --all -q && git checkout '${REPO_BRANCH}' -q && git reset --hard 'origin/${REPO_BRANCH}' -q;
     else
        rm -rf '${REMOTE_APP_DIR}' && git clone --branch '${REPO_BRANCH}' --single-branch '${REPO_URL}' '${REMOTE_APP_DIR}';
     fi"

# ---- 4. secret env file (chmod 600, never in git) ----
SCP "$SECRET_ENV" "${REMOTE}:/home/student-admin/app.env"
SSH 'chmod 600 ~/app.env'

# ---- 5. venv + deps ----
SSH 'dpkg -s python3-venv >/dev/null 2>&1 || sudo apt-get install -qq -y python3-venv >/dev/null'
SSH "cd '${REMOTE_APP_DIR}' && python3 -m venv venv && ./venv/bin/pip install -q --upgrade pip && ./venv/bin/pip install -q -r requirements.txt"

# ---- 6. systemd service ----
SCP effectivechatbot.service "${REMOTE}:/tmp/effectivechatbot.service"
SSH "sed 's#__APP_DIR__#${REMOTE_APP_DIR}#g' /tmp/effectivechatbot.service | sudo tee /etc/systemd/system/effectivechatbot.service >/dev/null &&
     sudo systemctl daemon-reload && sudo systemctl enable effectivechatbot -q && sudo systemctl restart effectivechatbot && rm -f /tmp/effectivechatbot.service"

# ---- 7. verify (informational; the deploy itself is done at step 6). Non-fatal:
# a transient SSH throttle/timeout here must not report the whole deploy as failed.
echo "[deploy] waiting for app on :7860 ..."
SSH 'for i in $(seq 1 24); do curl -fsS -o /dev/null http://localhost:7860 && { echo "[deploy] app is UP"; exit 0; }; sleep 5; done;
     echo "[deploy] app not up yet (model may still be downloading). Recent logs:"; sudo systemctl status effectivechatbot --no-pager | tail -n 15' \
  || echo "[deploy] verify inconclusive (could not connect — likely transient SSH throttle); service was enabled+started in step 6."
echo "[deploy] done. App URL: http://${MACHINE}:7860  (or SSH-tunnel port 7860)"
