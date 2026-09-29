#!/bin/bash
# Defensive check for Case Study 2, extra credit #5 (Red-Teaming).
#
# Confirms YOUR VM only trusts YOUR key. Extra credit requires that no other
# team could access your machine, so this verifies:
#   1. the shared student-admin default key is REJECTED (good), and
#   2. your personal key (cs553_group) is ACCEPTED (good).
#
# Read-only: runs `hostname` and prints authorized_keys. Makes no changes.

set -u

PORT=${PORT:-22010}
MACHINE=${MACHINE:-paffenroth-23.dyn.wpi.edu}
DEFAULT_KEY=${DEFAULT_KEY:-$HOME/.ssh/student-admin_key}
MYKEY=${MYKEY:-$HOME/.ssh/cs553_group}
REMOTE="student-admin@${MACHINE}"

echo "== 1. Default student-admin key must be REJECTED =="
if ssh -i "$DEFAULT_KEY" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "$REMOTE" hostname 2>/dev/null; then
  echo "!! VULNERABLE: the default key still works. Run deploy.sh / lock down."
else
  echo "OK: default key rejected."
fi

echo
echo "== 2. Your personal key must be ACCEPTED =="
if ssh -i "$MYKEY" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "$REMOTE" hostname 2>/dev/null; then
  echo "OK: your key works."
else
  echo "!! Your key ($MYKEY) did not authenticate. Check the path / deployment."
fi

echo
echo "== 3. authorized_keys on the VM (should contain ONLY your key) =="
ssh -i "$MYKEY" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "$REMOTE" "cat ~/.ssh/authorized_keys" 2>/dev/null
