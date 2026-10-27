#!/usr/bin/env python3
"""Aldaris configuration core: resolve catalog selections, sync generated outside files.

mac-forge is the source of truth. The resolved selection lives in config-local/aldaris/active.json
(untracked); the only outside file currently owned is the `.model` subtree of Qwen Code's
settings.json, tracked in a manifest on the storage drive.
"""
import argparse
import copy
import ctypes
import datetime
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

FORGE_ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = FORGE_ROOT / 'configs/aldaris'
CATALOG = CONFIG_DIR / 'catalog'
LOCAL_DIR = FORGE_ROOT / 'config-local/aldaris'
ACTIVE = LOCAL_DIR / 'active.json'
KEYS_FILE = LOCAL_DIR / 'api-keys.json'
NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
MANIFEST_NAME = '.mac-forge-manifest.json'
OWNED_KEY = 'model'


class ConfigError(Exception):
    pass


def load_json(path):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        raise ConfigError(f'{path}: not found')
    except json.JSONDecodeError as error:
        raise ConfigError(f'{path}: invalid JSON ({error})')


def require(data, path, field, kind, nonempty=True):
    if field not in data:
        raise ConfigError(f'{path}: missing {field}')
    value = data[field]
    ok = isinstance(value, kind) and not isinstance(value, bool) if kind in (int, float, (int, float)) \
        else isinstance(value, kind)
    if not ok:
        raise ConfigError(f'{path}: {field} must be {getattr(kind, "__name__", kind)}')
    if nonempty and value in ('', [], {}):
        raise ConfigError(f'{path}: {field} must not be empty')
    return value


def chapter_file(chapter, name):
    if not isinstance(name, str) or not NAME.match(name):
        raise ConfigError(f'invalid {chapter} name: {name!r}')
    return CATALOG / chapter / f'{name}.json'


def load_chapter(chapter, name):
    path = chapter_file(chapter, name)
    if not path.is_file():
        raise ConfigError(f'unknown {chapter[:-1]}: {name}')
    data = load_json(path)
    require(data, path, 'id', str)
    if data['id'] != name:
        raise ConfigError(f'{path}: id must equal the file name')
    require(data, path, 'description', str)
    return data, path


def load_global():
    path = CATALOG / 'global.json'
    data = load_json(path)
    require(data, path, 'storageRoot', str)
    require(data, path, 'qwenSettings', str)
    if not os.path.isabs(data['storageRoot']):
        raise ConfigError(f'{path}: storageRoot must be absolute')
    return data


def ids(chapter):
    return sorted(p.stem for p in (CATALOG / chapter).glob('*.json'))


def expand_patterns(patterns, root):
    expanded = []
    for pattern in patterns:
        pattern = pattern.replace('{storageRoot}', root)
        expanded.append(str(Path.home()) + pattern[1:] if pattern.startswith('~') else pattern)
    return expanded


def storage_root():
    return load_global()['storageRoot']


def all_engine_patterns():
    root = storage_root()
    patterns = []
    for name in ids('engines'):
        engine, path = load_chapter('engines', name)
        found = require(engine, path, 'monitorProcessPatterns', list, nonempty=False)
        if not all(isinstance(p, str) and p for p in found):
            raise ConfigError(f'{path}: monitorProcessPatterns must be non-empty strings')
        patterns += expand_patterns(found, root)
    return patterns


def confirm(question):
    try:
        with open('/dev/tty') as tty:
            print(f'{question} [y/N] ', end='', file=sys.stderr, flush=True)
            return tty.readline().strip().lower() == 'y'
    except OSError:
        raise ConfigError('no terminal available to confirm; rerun with --yes')


def resolve(engine_id, model_id, context, preset_id, profile=None):
    engine, epath = load_chapter('engines', engine_id)
    model, mpath = load_chapter('models', model_id)
    preset, ppath = load_chapter('presets', preset_id)
    glob = load_global()
    adapter = require(engine, epath, 'adapter', str)
    if not NAME.match(adapter) or not (FORGE_ROOT / 'scripts/aldaris-engines' / f'{adapter}.sh').is_file():
        raise ConfigError(f'{epath}: adapter {adapter!r} has no scripts/aldaris-engines/{adapter}.sh')
    host = require(engine, epath, 'host', str)
    port = require(engine, epath, 'port', int)
    formats = require(engine, epath, 'formats', list)
    api_key = require(engine, epath, 'apiKey', str)
    idle = require(engine, epath, 'idleSeconds', int)
    patterns = require(engine, epath, 'monitorProcessPatterns', list, nonempty=False)
    if not all(isinstance(p, str) and p for p in patterns):
        raise ConfigError(f'{epath}: monitorProcessPatterns must be non-empty strings')
    fmt = require(model, mpath, 'format', str)
    max_context = require(model, mpath, 'maxContext', int)
    contexts = require(model, mpath, 'contexts', list)
    model_engines = require(model, mpath, 'engines', dict)
    if engine_id not in model_engines or not isinstance(model_engines[engine_id], dict):
        raise ConfigError(f'model {model_id} is not configured for engine {engine_id}')
    served = require(model_engines[engine_id], f'{mpath} engines.{engine_id}', 'servedId', str)
    model_key = model_engines[engine_id].get('key', '')
    require(model, mpath, 'repository', str)
    for field in ('timeout', 'max_tokens', 'top_k'):
        require(preset, ppath, field, int)
    for field in ('temperature', 'top_p'):
        require(preset, ppath, field, (int, float))
    if fmt not in formats:
        raise ConfigError(f'model {model_id} format {fmt} is not accepted by engine {engine_id} ({", ".join(formats)})')
    if not isinstance(context, int) or isinstance(context, bool) or context not in contexts \
            or context > max_context:
        raise ConfigError(f'context {context} is not offered by model {model_id} ({", ".join(map(str, contexts))})')
    if adapter == 'lmstudio' and not (isinstance(model_key, str) and model_key):
        raise ConfigError(f'{mpath}: missing engines.{engine_id}.key')
    if not all(isinstance(c, int) and not isinstance(c, bool) for c in contexts):
        raise ConfigError(f'{mpath}: contexts must be integers')
    if KEYS_FILE.is_file():
        if KEYS_FILE.stat().st_mode & 0o077:
            print(f'aldaris-config: warning: {KEYS_FILE} is readable by others; chmod 600', file=sys.stderr)
        override = load_json(KEYS_FILE).get(engine_id)
        if isinstance(override, str) and override:
            api_key = override
    qwen_model = {
        'name': served,
        'generationConfig': {
            'contextWindowSize': context,
            'timeout': preset['timeout'],
            'samplingParams': {'temperature': preset['temperature'], 'top_p': preset['top_p'],
                               'max_tokens': preset['max_tokens']},
            'extra_body': {'top_k': preset['top_k']},
        },
    }
    return {
        'profile': profile, 'engine': engine_id, 'adapter': adapter, 'modelId': model_id,
        'model': served, 'modelKey': model_key, 'modelPath': model['repository'], 'contextLength': context,
        'preset': preset_id, 'host': host, 'port': port, 'baseUrl': f'http://{host}:{port}/v1',
        'apiKey': api_key, 'idleSeconds': idle, 'storageRoot': glob['storageRoot'],
        'monitorProcessPatterns': expand_patterns(patterns, glob['storageRoot']), 'qwenModel': qwen_model,
    }


def resolve_profile(name):
    path = CONFIG_DIR / 'profiles' / f'{name}.json'
    if not NAME.match(name) or not path.is_file():
        raise ConfigError(f'unknown profile: {name}')
    data = load_json(path)
    return resolve(require(data, path, 'engine', str), require(data, path, 'model', str),
                   require(data, path, 'context', int), require(data, path, 'preset', str), name)


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read_manifest(root):
    path = Path(root) / MANIFEST_NAME
    if not path.is_file():
        return {'version': 1, 'entries': []}
    data = load_json(path)
    if not isinstance(data.get('entries'), list):
        raise ConfigError(f'{path}: invalid manifest')
    return data


def atomic_write(path, text, mode=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temp = tempfile.mkstemp(dir=path.parent, prefix=f'.{path.name}.')
    try:
        with os.fdopen(handle, 'w') as out:
            out.write(text)
        if mode is None and path.exists():
            mode = path.stat().st_mode & 0o777
        os.chmod(temp, mode if mode is not None else 0o644)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def dump(value):
    return json.dumps(value, indent=2) + '\n'


def settings_path(resolved):
    return Path(resolved['storageRoot']) / load_global()['qwenSettings']


def plan_settings(resolved):
    path = settings_path(resolved)
    if path.is_file():
        current = load_json(path)
    else:
        current = load_json(CONFIG_DIR / 'qwen-settings.json')
    updated = copy.deepcopy(current)
    updated[OWNED_KEY] = resolved['qwenModel']
    return path, current, updated, path.is_file()


def find_entry(manifest, path):
    return next((e for e in manifest['entries'] if e.get('path') == str(path)), None)


def cmd_apply(args):
    resolved = json.load(sys.stdin)
    root = Path(resolved['storageRoot'])
    if not root.is_dir():
        raise ConfigError(f'storage root not mounted: {root}')
    path, current, updated, existed = plan_settings(resolved)
    manifest = read_manifest(root)
    entry = find_entry(manifest, path)
    drift = bool(entry and existed and entry['hash'] != canonical_hash(current.get(OWNED_KEY)))
    diff = list(difflib.unified_diff(dump(current).splitlines(), dump(updated).splitlines(),
                                     f'{path} (current)', f'{path} (new)', lineterm=''))
    print(f'Qwen settings: {path}' + ('' if existed else ' (will be created)'))
    print('\n'.join(diff) if diff else 'No changes to the outside files.')
    if drift:
        print(f'DRIFT: .{OWNED_KEY} in {path} was changed outside mac-forge since the last apply.')
    if args.dry_run:
        return
    if drift and not args.yes and not confirm('Overwrite the outside change?'):
        raise ConfigError('aborted; outside file left unchanged')
    record = {'path': str(path), 'ownership': 'keys', 'keys': [f'.{OWNED_KEY}'], 'engine': None,
              'hash': canonical_hash(updated[OWNED_KEY]),
              'updated': datetime.datetime.now().astimezone().isoformat(timespec='seconds')}
    manifest['entries'] = [e for e in manifest['entries'] if e.get('path') != str(path)] + [record]
    atomic_write(root / MANIFEST_NAME, dump(manifest), 0o644)
    if diff:
        atomic_write(path, dump(updated))
    atomic_write(ACTIVE, dump(resolved), 0o600)
    LOCAL_DIR.chmod(0o700)
    print(f'Active selection written to {ACTIVE}')


def cmd_status(_args):
    if not ACTIVE.is_file():
        print('No active Aldaris configuration (run aldaris-configure).')
        return 1
    active = load_json(ACTIVE)
    print(f"Active: {active.get('profile') or '(unsaved)'} — {active['engine']} / {active['modelId']} / "
          f"{active['contextLength']} / {active['preset']}")
    root = Path(active['storageRoot'])
    if not root.is_dir():
        print(f'Storage root not mounted: {root}')
        return 1
    manifest = read_manifest(root)
    status = 0
    for entry in manifest['entries']:
        path = Path(entry['path'])
        if not path.is_file():
            print(f'MISSING {path}')
            status = 1
            continue
        owned = load_json(path).get(entry['keys'][0].lstrip('.'))
        state = 'ok' if canonical_hash(owned) == entry['hash'] else 'DRIFT'
        if state == 'ok' and owned != active['qwenModel']:
            state = 'STALE (differs from active selection; run apply)'
        print(f'{state:8} {path} ({", ".join(entry["keys"])})')
        status = status or (state != 'ok')
    if not manifest['entries']:
        print('Manifest is empty (run apply).')
        status = 1
    return status


def cmd_clean(args):
    if not NAME.match(args.engine):
        raise ConfigError(f'invalid engine name: {args.engine}')
    root = Path(load_global()['storageRoot'])
    manifest = read_manifest(root)
    targets = [e for e in manifest['entries'] if e.get('engine') == args.engine]
    if not targets:
        print(f'Nothing recorded for engine {args.engine}. Engine trees, models and Qwen sessions are never removed.')
        return
    for entry in targets:
        print(f"{entry['ownership']}: {entry['path']} {' '.join(entry['keys'])}")
    if not args.yes and not confirm('Remove the listed files/keys?'):
        raise ConfigError('aborted')
    for entry in targets:
        path = Path(entry['path'])
        if path.is_file():
            if entry['ownership'] == 'file':
                path.unlink()
            else:
                data = load_json(path)
                for key in entry['keys']:
                    data.pop(key.lstrip('.'), None)
                atomic_write(path, dump(data))
    manifest['entries'] = [e for e in manifest['entries'] if e not in targets]
    atomic_write(root / MANIFEST_NAME, dump(manifest), 0o644)


def cmd_verify(_args):
    if not ACTIVE.is_file():
        raise ConfigError('no active configuration; run aldaris-configure')
    active = load_json(ACTIVE)
    fresh = resolve(active.get('engine'), active.get('modelId'), active.get('contextLength'),
                    active.get('preset'), active.get('profile'))
    if fresh != active:
        changed = sorted(k for k in set(fresh) | set(active) if fresh.get(k) != active.get(k))
        raise ConfigError(f'catalog changed since apply ({", ".join(changed)}); run aldaris-configure apply')
    profile = active.get('profile')
    if profile and (CONFIG_DIR / 'profiles' / f'{profile}.json').is_file() and resolve_profile(profile) != active:
        raise ConfigError(f'profile {profile} changed since apply; run aldaris-configure apply {profile}')
    path = settings_path(active)
    entry = find_entry(read_manifest(active['storageRoot']), path)
    current = load_json(path).get(OWNED_KEY) if path.is_file() else None
    if current != active['qwenModel'] or not entry or entry['hash'] != canonical_hash(current):
        raise ConfigError(f'{path} .{OWNED_KEY} differs from the active selection; run aldaris-configure apply')


def cmd_engines(_args):
    for name in ids('engines'):
        engine, _ = load_chapter('engines', name)
        print(f"{name}\t{engine['adapter']}")


_LIBPROC = []


# The kernel's executable path; unlike ps comm it survives a process renaming its title (oMLX does).
def executable_path(pid):
    try:
        if not _LIBPROC:
            _LIBPROC.append(ctypes.CDLL('/usr/lib/libproc.dylib'))
        buf = ctypes.create_string_buffer(4096)
        size = _LIBPROC[0].proc_pidpath(pid, buf, 4096)
    except OSError:
        return ''
    return buf.raw[:size].decode(errors='replace') if size > 0 else ''


def matches(fragments, pid, comm):
    return any(f in comm for f in fragments) or any(f in executable_path(pid) for f in fragments)


def running_pids(fragments):
    out = subprocess.run(['/bin/ps', '-axo', 'pid=,comm='], capture_output=True, text=True, timeout=5).stdout
    pids = []
    for line in out.splitlines():
        pid, _, comm = line.strip().partition(' ')
        if pid.isdigit() and int(pid) != os.getpid() and matches(fragments, int(pid), comm):
            pids.append(int(pid))
    return pids


def cmd_stop_processes(args):
    root = storage_root()
    if args.except_engine:
        fragments = []
        for name in ids('engines'):
            if name != args.except_engine:
                engine, path = load_chapter('engines', name)
                fragments += expand_patterns(require(engine, path, 'monitorProcessPatterns', list, nonempty=False), root)
    else:
        fragments = all_engine_patterns() + [f'{root}/tools/qwen-code/']
    if not fragments:
        return
    for sig, wait in ((signal.SIGTERM, 10), (signal.SIGKILL, 3)):
        pids = running_pids(fragments)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + wait
        while time.time() < deadline and running_pids(fragments):
            time.sleep(0.5)


def cmd_list(args):
    if args.chapter == 'profiles':
        for path in sorted((CONFIG_DIR / 'profiles').glob('*.json')):
            data = load_json(path)
            print(f"{path.stem}\t{data.get('description', '')}")
        return
    for name in ids(args.chapter):
        data, _ = load_chapter(args.chapter, name)
        if args.chapter == 'models':
            engine = load_chapter('engines', args.engine)[0] if args.engine else None
            if engine and (data.get('format') not in engine.get('formats', [])
                           or args.engine not in data.get('engines', {})):
                continue
            key = data.get('engines', {}).get(args.engine, {}).get('key', '') if args.engine else ''
            print(f"{name}\t{data['description']}\t{data.get('quantization', '')}\t"
                  f"{data.get('diskSizeGb', '?')} GB\t{key}")
        else:
            print(f"{name}\t{data['description']}")


def cmd_contexts(args):
    model, path = load_chapter('models', args.model)
    for value in require(model, path, 'contexts', list):
        if not isinstance(value, int) or isinstance(value, bool):
            raise ConfigError(f'{path}: contexts must be integers')
        if value <= model.get('maxContext', 0):
            print(value)


def cmd_catalog(args):
    print(dump(load_chapter(args.chapter, args.name)[0]), end='')


def cmd_resolve(args):
    if args.profile:
        resolved = resolve_profile(args.profile)
    else:
        if None in (args.engine, args.model, args.context, args.preset):
            raise ConfigError('resolve needs --profile or all of --engine --model --context --preset')
        resolved = resolve(args.engine, args.model, args.context, args.preset)
    print(dump(resolved), end='')


def cmd_save(args):
    if not NAME.match(args.name):
        raise ConfigError(f'invalid profile name: {args.name}')
    active = load_json(ACTIVE)
    resolve(active['engine'], active['modelId'], active['contextLength'], active['preset'])
    path = CONFIG_DIR / 'profiles' / f'{args.name}.json'
    if path.exists() and not args.force:
        raise ConfigError(f'profile exists: {args.name} (use --force)')
    data = {'description': args.description or f"{active['engine']} + {active['modelId']}, {active['contextLength']} context",
            'engine': active['engine'], 'model': active['modelId'], 'context': active['contextLength'],
            'preset': active['preset']}
    atomic_write(path, dump(data), 0o644)
    active['profile'] = args.name
    atomic_write(ACTIVE, dump(active), 0o600)
    print(f'Saved profile {args.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('resolve')
    p.add_argument('--profile')
    p.add_argument('--engine')
    p.add_argument('--model')
    p.add_argument('--context', type=int)
    p.add_argument('--preset')
    p.set_defaults(run=cmd_resolve)
    p = sub.add_parser('apply')
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--yes', action='store_true')
    p.set_defaults(run=cmd_apply)
    sub.add_parser('status').set_defaults(run=cmd_status)
    sub.add_parser('verify').set_defaults(run=cmd_verify)
    sub.add_parser('engines').set_defaults(run=cmd_engines)
    p = sub.add_parser('stop-processes')
    p.add_argument('--except', dest='except_engine')
    p.set_defaults(run=cmd_stop_processes)
    p = sub.add_parser('clean')
    p.add_argument('engine')
    p.add_argument('--yes', action='store_true')
    p.set_defaults(run=cmd_clean)
    p = sub.add_parser('list')
    p.add_argument('chapter', choices=['profiles', 'engines', 'models', 'presets'])
    p.add_argument('--engine')
    p.set_defaults(run=cmd_list)
    p = sub.add_parser('contexts')
    p.add_argument('model')
    p.set_defaults(run=cmd_contexts)
    p = sub.add_parser('catalog')
    p.add_argument('chapter', choices=['engines', 'models', 'presets'])
    p.add_argument('name')
    p.set_defaults(run=cmd_catalog)
    p = sub.add_parser('save')
    p.add_argument('name')
    p.add_argument('--description')
    p.add_argument('--force', action='store_true')
    p.set_defaults(run=cmd_save)
    args = parser.parse_args()
    try:
        sys.exit(args.run(args) or 0)
    except ConfigError as error:
        print(f'aldaris-config: {error}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
