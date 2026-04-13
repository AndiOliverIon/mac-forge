#!/usr/bin/env bash
set -euo pipefail

MODE="pretty"
if [[ "${1:-}" == "--json" || "${1:-}" == "-j" ]]; then
  MODE="json"
  shift
fi

if (($# > 0)); then
  echo "Usage: $(basename "$0") [--json]" >&2
  exit 1
fi

exec python3 - "$MODE" <<'PY'
import json
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

mode = sys.argv[1]


def resolve_command(provider_id: str):
    if provider_id == "copilot":
        if shutil.which("copilot"):
            return ["copilot"]
        if shutil.which("gh"):
            return ["gh", "copilot", "--"]
        return None
    if provider_id == "codex":
        return ["codex", "--no-alt-screen"] if shutil.which("codex") else None
    if provider_id == "gemini":
        return ["gemini"] if shutil.which("gemini") else None
    if provider_id == "claude":
        return ["claude", "--bare"] if shutil.which("claude") else None
    return None


def kill_process_group(proc: subprocess.Popen):
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    time.sleep(0.5)
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_probe(command):
    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(
        command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        preexec_fn=os.setsid,
        close_fds=True,
    )
    os.close(slave_fd)

    output = bytearray()
    start = time.time()
    sent_status = False
    sent_usage = False
    sent_interrupt = False

    try:
        while time.time() - start < 22:
            ready, _, _ = select.select([master_fd], [], [], 0.4)
            if ready:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)

                compact = re.sub(rb"\s+", b" ", bytes(output))
                if (
                    b"Enter to confirm" in bytes(output)
                    or b"Entertoconfirm" in compact
                    or b"Quicksafetycheck" in compact
                ):
                    os.write(master_fd, b"\r")

            elapsed = time.time() - start
            if elapsed >= 5 and not sent_status:
                os.write(master_fd, b"/status\r")
                sent_status = True
            if elapsed >= 10 and not sent_usage:
                os.write(master_fd, b"/usage\r")
                sent_usage = True
            if elapsed >= 15 and not sent_interrupt:
                os.write(master_fd, b"\x03")
                sent_interrupt = True

            if proc.poll() is not None and sent_interrupt:
                break
    finally:
        kill_process_group(proc)
        try:
            os.close(master_fd)
        except OSError:
            pass
        try:
            proc.wait(timeout=1)
        except Exception:
            pass

    return output.decode("utf-8", errors="replace")


def parse_provider(provider_id: str, label: str) -> dict:
    command = resolve_command(provider_id)
    result = {
        "id": provider_id,
        "label": label,
        "installed": command is not None,
        "probe_status": "unknown",
        "quota_state": "unknown",
        "remaining_percent": None,
        "remaining_hint": None,
        "summary": "Usage could not be parsed from CLI output.",
    }

    if command is None:
        result["probe_status"] = "not_installed"
        result["summary"] = "CLI not installed or not available on PATH."
        return result

    raw = run_probe(command)
    compact = " ".join(raw.split())

    if not compact:
        result["probe_status"] = "no_output"
        result["summary"] = "Probe returned no output."
        return result

    if "Waiting for authentication" in compact:
        result["probe_status"] = "auth_required"
        result["summary"] = "Interactive authentication blocked the usage probe."
        return result

    if (
        "Itrustthisfolder" in compact
        or "Entertoconfirm" in compact
        or "Enter to confirm" in compact
        or "Quicksafetycheck" in compact
    ):
        result["probe_status"] = "trust_required"
        result["summary"] = "Workspace trust confirmation blocked the usage probe."
        return result

    low_match = re.search(r"less than\s+(\d+)%\s+of your .*? limit left", compact, re.IGNORECASE)
    if low_match:
        ceiling = int(low_match.group(1))
        result["probe_status"] = "ok"
        result["quota_state"] = "low"
        result["remaining_hint"] = f"<{ceiling}%"
        result["summary"] = low_match.group(0)
        return result

    exact_match = re.search(r"(\d+)%\s+of your .*? limit left", compact, re.IGNORECASE)
    if exact_match:
        remaining = int(exact_match.group(1))
        result["probe_status"] = "ok"
        result["quota_state"] = "low" if remaining < 25 else "ok"
        result["remaining_percent"] = remaining
        result["summary"] = exact_match.group(0)
        return result

    if re.search(r"quota exceeded|limit reached|weekly limit reached|rate limit|out of credits", compact, re.IGNORECASE):
        result["probe_status"] = "ok"
        result["quota_state"] = "exhausted"
        result["remaining_percent"] = 0
        result["summary"] = "Quota appears exhausted or rate-limited."
        return result

    plan_match = re.search(r"Plan:\s+(.+?)(?:/upgrade|$)", compact, re.IGNORECASE)
    if plan_match:
        result["probe_status"] = "unparsed"
        result["summary"] = f"Signed in ({plan_match.group(1).strip()}); usage not parsed."
        return result

    if "Signed in with Google" in compact:
        result["probe_status"] = "unparsed"
        result["summary"] = "Gemini is signed in, but usage output was not parsed."
        return result

    if "To continue this session, run codex resume" in compact:
        result["probe_status"] = "unparsed"
        result["summary"] = "Codex session started, but usage output was not parsed."
        return result

    if "GitHub Copilot CLI" in compact or "copilot" in compact.lower():
        result["probe_status"] = "unparsed"
        result["summary"] = "Copilot started, but usage output was not parsed."
        return result

    result["probe_status"] = "unparsed"
    return result


providers = [
    ("copilot", "GitHub Copilot"),
    ("codex", "Codex"),
    ("gemini", "Gemini"),
    ("claude", "Claude"),
]

results = [parse_provider(provider_id, label) for provider_id, label in providers]
payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "agents": results,
}

if mode == "json":
    print(json.dumps(payload, indent=2))
    raise SystemExit(0)

label_width = max(len(item["label"]) for item in results)
status_width = max(len(item["probe_status"]) for item in results)
quota_width = max(len(item["quota_state"]) for item in results)

print("AI usage")
print()
for item in results:
    remaining = str(item["remaining_percent"]) if item["remaining_percent"] is not None else (item["remaining_hint"] or "-")
    print(
        f"{item['label']:<{label_width}}  "
        f"status={item['probe_status']:<{status_width}}  "
        f"quota={item['quota_state']:<{quota_width}}  "
        f"remaining={remaining:<4}  "
        f"{item['summary']}"
    )
PY
