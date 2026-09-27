#!/usr/bin/env python3
"""The whisper.cpp model for voice dictation. JSON line events.

    speech.py status | install | remove

The engine is the distribution's whisper-cli; only the model is fetched here,
pinned by revision and verified by SHA-256, as manifests/speech.toml says.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
import urllib.request

MANIFEST = json.loads(Path(__file__).with_name('speech.json').read_text())['model']
ROOT = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / '0xide/speech'
MODEL = ROOT / MANIFEST['file']


def emit(**data):
    print(json.dumps(data), flush=True)


def status():
    missing = [tool for tool in ('whisper-cli', 'pw-record', 'wtype') if not shutil.which(tool)]
    ancestor = ROOT
    while not ancestor.exists():
        ancestor = ancestor.parent
    return {'installed': MODEL.is_file() and MODEL.stat().st_size == MANIFEST['bytes'],
            'model': MANIFEST['file'], 'downloadBytes': MANIFEST['bytes'],
            'freeBytes': shutil.disk_usage(ancestor).free, 'destination': str(ROOT), 'missing': missing}


def install():
    if status()['installed']:
        emit(stage='installed', **status())
        return
    url = f"https://huggingface.co/{MANIFEST['repo']}/resolve/{MANIFEST['revision']}/{MANIFEST['file']}"
    partial = MODEL.with_name(MODEL.name + '.partial')
    digest, count, last = hashlib.sha256(), 0, 0.0
    request = urllib.request.Request(url, headers={'User-Agent': '0xide-speech/1'})
    with urllib.request.urlopen(request, timeout=60) as response, partial.open('wb') as output:
        while block := response.read(1024 * 1024):
            count += len(block)
            if count > MANIFEST['bytes']:
                raise RuntimeError('Download exceeds the expected model size')
            output.write(block)
            digest.update(block)
            if time.monotonic() - last > .25:
                emit(stage='download', bytes=count, total=MANIFEST['bytes'])
                last = time.monotonic()
    if count != MANIFEST['bytes'] or digest.hexdigest() != MANIFEST['sha256']:
        partial.unlink(missing_ok=True)
        raise RuntimeError('The downloaded model does not match its pinned hash')
    partial.rename(MODEL)
    emit(stage='installed', **status())


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ''
    if action not in ('status', 'install', 'remove'):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if action == 'status':
            emit(stage='status', **status())
            return 0
        ROOT.mkdir(parents=True, exist_ok=True)
        with (ROOT / '.lock').open('w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('The speech model is already being installed') from None
            if action == 'install':
                install()
            else:
                MODEL.unlink(missing_ok=True)
                emit(stage='removed', **status())
    except KeyboardInterrupt:
        emit(stage='cancelled')
        return 130
    except Exception as error:
        emit(stage='error', error=str(error))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
