#!/usr/bin/python3
"""Read-only live resource monitor for the local Aldaris stack on macOS."""
import argparse
import ctypes
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


def cpu_ticks(mach, host):
    ticks = (ctypes.c_uint32 * 4)()
    count = ctypes.c_uint32(4)
    if mach.host_statistics(host, 3, ticks, ctypes.byref(count)) != 0:
        return None
    return tuple(ticks)


def memory_used():
    try:
        raw = command(['/usr/bin/vm_stat'])
        page_size = int(re.search(r'page size of (\d+) bytes', raw).group(1))
        values = {name.strip(): int(value) for name, value in
                  re.findall(r'^([^:\n]+):\s+(\d+)\.', raw, re.MULTILINE)}
        pages = (values['Anonymous pages'] - values['Pages purgeable']
                 + values['Pages wired down'] + values['Pages occupied by compressor'])
        return f'{max(0, pages) * page_size / 1073741824:.1f} GiB'
    except (RuntimeError, subprocess.TimeoutExpired, KeyError, AttributeError, ValueError):
        return 'unavailable'


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
    mach = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    host = mach.mach_host_self()
    cores = os.cpu_count() or 1
    previous_ticks = None
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
            ticks = cpu_ticks(mach, host)
            system_cpu = '…'
            if ticks is not None and previous_ticks is not None:
                deltas = [(new - old) % (2 ** 32) for new, old in zip(ticks, previous_ticks)]
                total = sum(deltas)
                if total:
                    system_cpu = f'{100 * (total - deltas[2]) / total:.1f}%'
            junior_cpu = 0.0
            junior_rss = 0.0
            for pid, row in current.items():
                old = previous.get(pid)
                if elapsed and old and row['executable'] == old['executable'] and row['used'] >= old['used']:
                    junior_cpu += 100 * (row['used'] - old['used']) / elapsed / cores
                junior_rss += row['rss']
            junior_reading = f'{junior_cpu:.1f}%' if elapsed else '…'
            lines = [f'JUNIOR CHECK   {datetime.datetime.now():%H:%M:%S}   Ctrl+C exits', '',
                     f'{"":8} {"Total":>14} {"Junior":>14}',
                     f'{"GPU":8} {gpu_usage():>14} {"unavailable*":>14}',
                     f'{"MEM":8} {memory_used():>14} {f"{junior_rss:.1f} GiB":>14}',
                     f'{"CPU":8} {system_cpu:>14} {junior_reading:>14}', '',
                     '* GPU: macOS exposes whole-Mac usage only.',
                     'CPU: % of the whole Mac. Junior MEM: process RSS sum (shared pages may overlap).']
            previous_ticks = ticks
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
