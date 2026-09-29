# Operations: Deploy, Recovery, Monitoring (Case Study 2)

Covers deliverables 3a (automated deploy), 3b (auto recovery), 3c (resilience
testing), and extra credit #6 (resource monitoring). Fill in `<...>` values.

## Resilience model
| Layer | Handles | Mechanism |
|---|---|---|
| Local supervision | app crash, VM reboot | `systemd` unit `effectivechatbot`, `Restart=always`, enabled |
| External recovery | full wipe, VM down | `recovery.sh` via cron on `linux.wpi.edu` |
| Lockdown | red-team / EC #5 | deploy installs your key + removes default; recovery re-locks after a wipe |

## 0. Discord webhook (EC #6)
1. Discord server → **Server Settings → Integrations → Webhooks → New Webhook**.
2. Pick a channel, **Copy Webhook URL**.
3. `cp app.env.example app.env`, put the URL in `DISCORD_WEBHOOK_URL=`, `chmod 600 app.env`.
   - `app.env` is gitignored. Never commit it. To demo the alert, set e.g.
     `MONITOR_CPU_THRESHOLD=5` so it trips immediately.

## 1. First deploy (from your laptop)
VM = port **22010** (host `group10`); personal key `~/.ssh/cs553_group`; default
key `~/.ssh/student-admin_key` (used only to recover a wiped VM). Override via env.
```bash
export REPO_URL=https://github.com/<you>/<repo>.git   # your repo, case_study_2 branch
./deploy.sh
```
What it does (idempotent, anti-lockout): picks whichever key works → adds your
key and **verifies login before removing the default** → clones/updates your
repo → copies `app.env` (600) → venv + `requirements.txt` → installs & starts
the `systemd` service → polls `http://<vm>:7860`.

Verify lockdown afterward:
```bash
./check_lockdown.sh    # default key must be REJECTED, your key ACCEPTED
```

## 2. Auto-recovery on linux.wpi.edu (deliverable 3b)
```bash
ssh <you>@linux.wpi.edu
git clone <your repo> ~/cs2 && cd ~/cs2
mkdir -p keys && chmod 700 keys
# scp from laptop: keys/cs553_group[.pub] and keys/student-admin_key ; then chmod 600 keys/*
cp app.env.example app.env && edit app.env   # DISCORD_WEBHOOK_URL, chmod 600
crontab -e
# add (runs every 5 min):
*/5 * * * * REPO_URL=https://github.com/<you>/<repo>.git BASE=$HOME/cs2 $HOME/cs2/recovery.sh
tail -f ~/cs2/recovery.log
```
`recovery.sh` states: your key + app up → nothing; app down → `systemctl
restart`; only default key → **wiped**, full redeploy + re-lock; neither →
retry next tick.

## 3. Resilience testing (deliverable 3c)
- **App crash:** `sudo systemctl kill effectivechatbot` → systemd restarts it in
  ~5s (local layer). Confirm with `systemctl status` / `curl :7860`.
- **Disable local supervision + kill:** `sudo systemctl stop effectivechatbot`
  → within 5 min `recovery.sh` restarts it. Check `recovery.log`.
- **Simulated wipe / lockout:** re-add the default key and remove yours on the
  VM (or wait for a real wipe). recovery.sh detects "only default key" and does
  a full redeploy + re-lock. Screenshot `recovery.log` showing the transition.
- **Monitoring (EC #6):** with `MONITOR_CPU_THRESHOLD=5`, load the CPU
  (`yes >/dev/null &` a few times) → Discord alert fires, app offloads local
  model to the API; `kill %1 ...` → recovery alert, local model re-enabled.

## Notes
- Secrets: keys live in `tmp/` and on linux.wpi.edu (600); webhook in `app.env`
  (600). None are committed (see `.gitignore`).
- The app **requires** `DISCORD_WEBHOOK_URL`; deploy aborts if `app.env` lacks it.
