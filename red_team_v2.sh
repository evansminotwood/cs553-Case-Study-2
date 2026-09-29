#!/bin/bash
# Red-Teaming for Case Study 2, extra credit #5 (hardened version of
# red_team_v1.sh). Professor-sanctioned window: noon Sept 29 -> noon Oct 1, 2026.
#
# RULES (from the assignment) — do not break these or you forfeit the credit:
#   * Access + timestamped screenshot ONLY.
#   * Do NOT change/remove files, edit config, leave a backdoor, or touch
#     hardware/memory. This script only runs `hostname` (read-only).
#   * NO port scanning — it will get your IP banned by WPI security. This tries
#     only the assigned per-group SSH ports, one at a time, and throttles.
#   * Tell any team whose machine you access; make no changes.
#
# It simply tries the shared student-admin key against each group's assigned
# port. A group that replaced the default key will refuse the connection.

set -u

NUM_GROUPS=${NUM_GROUPS:-21}
BASE_PORT=${BASE_PORT:-22000}
MACHINE=${MACHINE:-paffenroth-23.dyn.wpi.edu}
KEY=${KEY:-$HOME/.ssh/student-admin_key}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-4}   # throttle so we don't look like a scanner

# BatchMode: never prompt for a password (fail fast if the key is rejected).
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=6"

for i in $(seq 1 "$NUM_GROUPS"); do
  port=$((BASE_PORT + i))
  echo "------------------------------------------------"
  echo "group ${i} @ ${MACHINE}:${port}"
  if ssh -i "$KEY" -p "$port" $SSH_OPTS student-admin@"$MACHINE" hostname 2>/dev/null; then
    echo ">> group ${i} is VULNERABLE (default key still authorized)"
  else
    echo "   group ${i} is protected."
  fi
  sleep "$SLEEP_BETWEEN"
done
