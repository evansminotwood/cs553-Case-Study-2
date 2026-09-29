"""Resource monitoring and adaptive response (Case Study 2, extra credit #6).

Samples CPU and system-memory usage in a background thread. When usage crosses
a configurable threshold the monitor:
  1. sends a Discord webhook notification to the team, and
  2. raises a "near capacity" flag that app.py reads to offload work from the
     local CPU model to the remote Inference API.

When usage drops back below the threshold (minus a recovery margin, for
hysteresis) the flag clears and a recovery notice is sent.

Thresholds are read from the environment so they can be set arbitrarily low for
testing:
  DISCORD_WEBHOOK_URL   (required) Discord incoming-webhook URL
  MONITOR_CPU_THRESHOLD (default 80)  percent CPU that triggers near-capacity
  MONITOR_MEM_THRESHOLD (default 80)  percent system memory that triggers it
  MONITOR_RECOVERY_MARGIN (default 10) percent below threshold to clear the flag
  MONITOR_INTERVAL      (default 5)   seconds between samples
"""

import os
import threading

import psutil
import requests


def _env_float(name, default):
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


class ResourceMonitor:
    def __init__(self):
        self.webhook_url = os.environ.get("DISCORD_WEBHOOK_URL")
        if not self.webhook_url:
            raise ValueError(
                "DISCORD_WEBHOOK_URL is required for resource monitoring. "
                "Set it in the environment before starting the app."
            )

        self.cpu_threshold = _env_float("MONITOR_CPU_THRESHOLD", 80.0)
        self.mem_threshold = _env_float("MONITOR_MEM_THRESHOLD", 80.0)
        self.recovery_margin = _env_float("MONITOR_RECOVERY_MARGIN", 10.0)
        self.interval = _env_float("MONITOR_INTERVAL", 5.0)

        self._near_capacity = False
        self._lock = threading.Lock()
        self._thread = None

    def start(self):
        if self._thread is not None:
            return
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        print(
            f"[MONITOR] started (cpu>={self.cpu_threshold}% "
            f"mem>={self.mem_threshold}% every {self.interval}s)"
        )

    def is_near_capacity(self):
        with self._lock:
            return self._near_capacity

    def snapshot(self):
        return {
            "cpu": psutil.cpu_percent(interval=None),
            "mem": psutil.virtual_memory().percent,
            "near_capacity": self.is_near_capacity(),
        }

    def _loop(self):
        # First cpu_percent call establishes the baseline and returns 0.0.
        psutil.cpu_percent(interval=None)
        while True:
            cpu = psutil.cpu_percent(interval=self.interval)
            mem = psutil.virtual_memory().percent
            self._evaluate(cpu, mem)

    def _evaluate(self, cpu, mem):
        over = cpu >= self.cpu_threshold or mem >= self.mem_threshold
        recovered = (
            cpu < self.cpu_threshold - self.recovery_margin
            and mem < self.mem_threshold - self.recovery_margin
        )

        with self._lock:
            was_near = self._near_capacity
            if over and not was_near:
                self._near_capacity = True
                transition = "breach"
            elif recovered and was_near:
                self._near_capacity = False
                transition = "recovery"
            else:
                transition = None

        if transition == "breach":
            print(f"[MONITOR] near capacity: cpu={cpu:.0f}% mem={mem:.0f}%")
            self._notify(
                f"⚠️ **Near capacity** — cpu={cpu:.0f}% mem={mem:.0f}% "
                f"(threshold cpu={self.cpu_threshold:.0f}% "
                f"mem={self.mem_threshold:.0f}%). "
                "Offloading local model to the remote Inference API."
            )
        elif transition == "recovery":
            print(f"[MONITOR] recovered: cpu={cpu:.0f}% mem={mem:.0f}%")
            self._notify(
                f"✅ **Recovered** — cpu={cpu:.0f}% mem={mem:.0f}%. "
                "Local model re-enabled."
            )

    def _notify(self, content):
        try:
            requests.post(self.webhook_url, json={"content": content}, timeout=10)
        except requests.RequestException as exc:
            print(f"[MONITOR] webhook failed: {exc}")
