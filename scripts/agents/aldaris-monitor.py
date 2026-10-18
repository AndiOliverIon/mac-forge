#!/usr/bin/python3
"""Read-only live resource monitor for the local Aldaris stack on macOS."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=4)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"{args[0]} failed")
    return result.stdout


def cpu_seconds(value):
    days, _, clock = value.rpartition('-')
    parts = [float(part) for part in clock.split(':')]
    seconds = sum(part * (60 ** index) for index, part in enumerate(reversed(parts)))
    return seconds + (int(days) * 86400 if days else 0)


def processes(ai_root):
    rows = {}
    raw = command(['/bin/ps', '-axo', 'pid=,ppid=,time=,rss=,comm='])
    for line in raw.splitlines():
        fields = line.strip().split(None, 4)
        if len(fields) != 5:
            continue
        pid, parent, used, rss, executable = fields
        rows[int(pid)] = dict(parent=int(parent), used=cpu_seconds(used),
                              rss=int(rss) / 1048576, executable=executable)
    selected = {}
    for pid, row in rows.items():
        executable = row['executable']
        if f'{ai_root}/tools/qwen-code/' in executable:
            selected[pid] = 'Qwen CLI'
        elif '/LM Studio.app/' in executable:
            selected[pid] = ('LM Studio UI' if executable.endswith('/MacOS/LM Studio')
                             else 'LM Studio helper')
        elif '/.lmstudio/' in executable or f'{ai_root}/lmstudio/' in executable:
            try:
                arguments = command(['/bin/ps', '-p', str(pid), '-o', 'command='])
            except RuntimeError:
                continue
            selected[pid] = ('INFERENCE worker' if 'llmworker.js' in arguments
                             else 'LM Studio service')
    # Include subprocesses spawned by the CLI or inference runtime, even if their
    # executable is a compiler or an interpreter outside the installation paths.
    changed = True
    while changed:
        changed = False
        for pid, row in rows.items():
            if pid not in selected and row['parent'] in selected:
                selected[pid] = f"child of {row['parent']}"
                changed = True
    return {pid: dict(rows[pid], label=label) for pid, label in selected.items()
            if pid != os.getpid()}


def gpu_usage():
    try:
        raw = subprocess.run(['/usr/sbin/ioreg', '-a', '-r', '-c', 'IOAccelerator'],
                             capture_output=True, timeout=4)
    except subprocess.TimeoutExpired:
        return 'unavailable'
    if raw.returncode:
        return 'unavailable'
    readings = []

    def visit(node):
        if isinstance(node, dict):
            stats = node.get('PerformanceStatistics', {})
            value = stats.get('Device Utilization %')
            if isinstance(value, (int, float)) and 0 <= value <= 100:
                readings.append(f'{value:.0f}%')
            for child in node.get('IORegistryEntryChildren', []):
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)
    try:
        visit(plistlib.loads(raw.stdout))
    except (ValueError, plistlib.InvalidFileException):
        return 'unavailable'
    return ', '.join(readings) or 'unavailable'


def memory_status():
    try:
        level = command(['/usr/sbin/sysctl', '-n', 'kern.memorystatus_vm_pressure_level']).strip()
        pressure = {'1': 'normal', '2': 'warning', '4': 'critical'}.get(level, 'unavailable')
        swap = command(['/usr/sbin/sysctl', 'vm.swapusage'])
        used = re.search(r'used\s*=\s*([\d.]+[MG])', swap)
        return pressure, used.group(1) if used else 'unavailable'
    except (RuntimeError, subprocess.TimeoutExpired):
        return 'unavailable', 'unavailable'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interval', type=float, default=1.0, help='refresh interval in seconds (default 1)')
    parser.add_argument('--samples', type=int, help='stop after this many readings (default: until Ctrl+C)')
    args = parser.parse_args()
    if not (0.2 <= args.interval <= 60) or (args.samples is not None and args.samples < 1):
        parser.error('interval must be 0.2–60 seconds; samples must be positive')
    if sys.platform != 'darwin':
        parser.error('this monitor requires macOS')
    config = Path(__file__).resolve().parents[2] / 'configs/aldaris/config.json'
    ai_root = json.loads(config.read_text())['storageRoot']
    previous = {}
    previous_at = None
    sample = 0
    terminal = sys.stdout.isatty()
    if terminal:
        sys.stdout.write('\033[?1049h\033[?25l')
    try:
        while True:
            started = time.monotonic()
            try:
                current = processes(ai_root)
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                print(f'Cannot read process metrics: {error}', file=sys.stderr)
                return 1
            now = time.monotonic()
            elapsed = now - previous_at if previous_at is not None else None
            pressure, swap = memory_status()
            lines = [f'ALDARIS LIVE  |  {datetime.datetime.now():%H:%M:%S}  |  refresh ~{args.interval:g}s  |  Ctrl+C exits',
                     f'GPU device utilization (WHOLE MAC): {gpu_usage()}',
                     f'Mac memory pressure: {pressure}  |  Mac swap used: {swap}', '',
                     f'{"PID":>7}  {"CPU %":>7}  {"RSS GiB":>8}  ROLE / EXECUTABLE']
            total_cpu = 0.0
            total_rss = 0.0
            for pid, row in sorted(current.items(), key=lambda item: -item[1]['rss']):
                old = previous.get(pid)
                cpu = None
                if elapsed and old and row['executable'] == old['executable'] and row['used'] >= old['used']:
                    cpu = 100 * (row['used'] - old['used']) / elapsed
                    total_cpu += cpu
                total_rss += row['rss']
                reading = f'{cpu:.1f}' if cpu is not None else '…'
                lines.append(f'{pid:7d}  {reading:>7}  {row["rss"]:8.2f}  {row["label"]} / {Path(row["executable"]).name}')
            if not current:
                lines.append('No local Aldaris / LM Studio processes found. Nothing will be started.')
            aggregate_cpu = f'{total_cpu:.1f}%' if elapsed else 'collecting baseline'
            lines += ['', f'Tracked CPU: {aggregate_cpu}  |  Sum RSS: {total_rss:.2f} GiB',
                      'CPU: interval measurement; 100% = one CPU core. First/new PID reading needs a second sample.',
                      'RSS is resident process memory; shared pages can be counted more than once.',
                      'GPU is shared across the Mac, not attributable to Aldaris alone. Unified GPU memory is not added to RSS.',
                      'All LM Studio/Qwen sessions are included. The UI GPU helper is not the inference worker.']
            if terminal:
                sys.stdout.write('\033[H\033[2J')
                width = shutil.get_terminal_size((120, 40)).columns
                lines = [line[:max(1, width - 1)] for line in lines]
            print('\n'.join(lines), flush=True)
            previous, previous_at = current, now
            sample += 1
            if args.samples is not None and sample >= args.samples:
                return 0
            time.sleep(max(0, args.interval - (time.monotonic() - started)))
    except KeyboardInterrupt:
        return 0
    finally:
        if terminal:
            sys.stdout.write('\033[?25h\033[?1049l')
            sys.stdout.flush()


if __name__ == '__main__':
    sys.exit(main())
