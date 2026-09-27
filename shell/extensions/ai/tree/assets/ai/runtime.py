#!/usr/bin/env python3
"""User-owned BitNet installation. JSON line events, no OS package mutations."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

MANIFEST = json.loads(Path(__file__).with_name('manifest.json').read_text())
ROOT = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / '0xide/ai'
# Where it lived before the rename; moved, not downloaded again.
LEGACY = ROOT.parent.parent / 'caelestia/ai'
if LEGACY.is_dir() and not LEGACY.is_symlink() and not ROOT.exists():
    ROOT.parent.mkdir(parents=True, exist_ok=True)
    LEGACY.rename(ROOT)
    try:
        LEGACY.parent.rmdir()
    except OSError:
        pass
REVISION = MANIFEST['runtimeRevision'][:12] + '-' + MANIFEST['modelRevision'][:12]
ACTIVE = ROOT / REVISION
CHILD = None


def emit(**data):
    print(json.dumps(data), flush=True)


def stop_child():
    global CHILD
    if CHILD is not None and CHILD.poll() is None:
        os.killpg(CHILD.pid, signal.SIGTERM)
        try:
            CHILD.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(CHILD.pid, signal.SIGKILL)
            CHILD.wait()
    CHILD = None


def terminate(signum=None, frame=None):
    # Unwind Popen.wait before cleanup; calling wait/poll from a signal handler
    # can deadlock on subprocess's non-reentrant waitpid lock.
    raise KeyboardInterrupt


def run(command, cwd, log):
    global CHILD
    with log.open('a') as output:
        CHILD = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=output, start_new_session=True)
        code = CHILD.wait()
    CHILD = None
    if code:
        raise RuntimeError(f'Command failed ({code}); details: {log}')


def preflight():
    missing = [tool for tool in ('git', 'cmake', 'ninja', 'clang', 'clang++') if not shutil.which(tool)]
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'aarch64'):
        missing.append('supported Linux x86_64 or aarch64 architecture')
    # Model plus source/build scratch space. Download itself has a fixed size.
    required = MANIFEST['modelBytes'] + 3 * 1024**3
    ancestor = ROOT
    while not ancestor.exists():
        ancestor = ancestor.parent
    return {'missing': missing, 'freeBytes': shutil.disk_usage(ancestor).free,
            'requiredBytes': required, 'downloadBytes': MANIFEST['modelBytes'],
            'destination': str(ROOT), 'installed': (ACTIVE / 'ready.json').exists(),
            'model': MANIFEST['model'], 'contextTokens': MANIFEST['contextTokens']}


def download(destination):
    url = f"https://huggingface.co/{MANIFEST['model']}/resolve/{MANIFEST['modelRevision']}/{MANIFEST['modelFile']}"
    digest = hashlib.sha256()
    count = 0
    last = 0.0
    request = urllib.request.Request(url, headers={'User-Agent': '0xide-local-ai/1'})
    with urllib.request.urlopen(request, timeout=60) as response, destination.open('wb') as output:
        while block := response.read(1024 * 1024):
            count += len(block)
            if count > MANIFEST['modelBytes']:
                raise RuntimeError('Download exceeds expected model size')
            output.write(block)
            digest.update(block)
            if time.monotonic() - last > .25:
                emit(stage='download', bytes=count, total=MANIFEST['modelBytes'])
                last = time.monotonic()
    if count != MANIFEST['modelBytes'] or digest.hexdigest() != MANIFEST['modelSha256']:
        raise RuntimeError('Model checksum or size mismatch')


def server_command(directory, port):
    # The pinned runtime carries BitNet's own chat template and token setup for
    # this model, so the server needs neither a template nor overrides.
    return [str(directory / 'runtime/build/bin/llama-server'), '-m', str(directory / MANIFEST['modelFile']),
            '--host', '127.0.0.1', '--port', str(port), '-c', str(MANIFEST['contextTokens']),
            '--parallel', '1', '--no-context-shift',
            '-n', str(MANIFEST['responseTokens']), '-t', str(max(1, min(4, (os.cpu_count() or 2) // 2))), '-ngl', '0']


# Installed revisions are named <runtime>-<model>, twelve hex digits each.
def revision_dirs():
    return [p for p in ROOT.glob('*-*') if p.is_dir() and not p.is_symlink()
            and len(p.name) == 25 and all(c in '0123456789abcdef-' for c in p.name)]


def reuse_model(destination):
    """Links a verified copy of the model from another installed revision, so a
    runtime update does not download 1.1 GiB again. False if there is none."""
    for other in revision_dirs():
        candidate = other / MANIFEST['modelFile']
        if other == ACTIVE or not candidate.is_file() or candidate.stat().st_size != MANIFEST['modelBytes']:
            continue
        digest = hashlib.sha256()
        with candidate.open('rb') as source:
            while block := source.read(4 * 1024 * 1024):
                digest.update(block)
        if digest.hexdigest() != MANIFEST['modelSha256']:
            continue
        try:
            os.link(candidate, destination)
        except OSError:
            shutil.copyfile(candidate, destination)
        return True
    return False


def build_runtime(runtime, log):
    """BitNet's own setup_env.py for the pinned revision, for the 2B model: its
    lookup-table kernels generated with the parameters setup_env gives this
    model, and built in. The generic I2_S path of later revisions computes wrong
    results for this model on some CPUs (fluent, wrong answers)."""
    arch = platform.machine().lower()
    if arch in ('x86_64', 'amd64'):
        codegen, flag = 'utils/codegen_tl2.py', '-DBITNET_X86_TL2=ON'
        sizes = ['--BM', '160,320,320', '--BK', '96,96,96', '--bm', '32,32,32']
    elif arch in ('aarch64', 'arm64'):
        codegen, flag = 'utils/codegen_tl1.py', '-DBITNET_ARM_TL1=ON'
        sizes = ['--BM', '160,320,320', '--BK', '64,128,64', '--bm', '32,64,32']
    else:
        raise RuntimeError(f'No BitNet kernels for {arch}')
    run([sys.executable, codegen, '--model', 'bitnet_b1_58-3B', *sizes], runtime, log)
    # This revision predates clang making incompatible pointer types an error.
    relax = '-Wno-error=incompatible-pointer-types'
    run(['cmake', '-S', '.', '-B', 'build', '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
         '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++', '-DBUILD_SHARED_LIBS=OFF', flag,
         f'-DCMAKE_C_FLAGS={relax}', f'-DCMAKE_CXX_FLAGS={relax}'], runtime, log)
    run(['cmake', '--build', 'build', '--target', 'llama-server', '-j', '2'], runtime, log)


def serve(directory, once=False):
    global CHILD
    # Reserve a candidate port, then verify only our child's readiness. A bind
    # conflict makes the child exit; never attach to an unrelated local server.
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    with (ROOT / 'server.log').open('a') as log:
        CHILD = subprocess.Popen(server_command(directory, port), stdout=log, stderr=log, start_new_session=True)
    for _ in range(180):
        if CHILD.poll() is not None:
            raise RuntimeError(f'Local server exited; see {ROOT / "server.log"}')
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=1) as response:
                if response.status == 200 and CHILD.poll() is None:
                    break
        except (OSError, urllib.error.URLError):
            time.sleep(1)
    else:
        raise RuntimeError('Local model did not become ready within 180 seconds')
    if once:
        os.killpg(CHILD.pid, signal.SIGTERM)
        CHILD.wait(timeout=10)
        CHILD = None
    else:
        emit(stage='ready', endpoint=f'http://127.0.0.1:{port}/v1/chat/completions')
        code = CHILD.wait()
        CHILD = None
        if code:
            raise RuntimeError(f'Local server stopped ({code})')


def install():
    info = preflight()
    if info['missing']:
        raise RuntimeError('Install prerequisites manually: ' + ', '.join(info['missing']))
    if info['freeBytes'] < info['requiredBytes']:
        raise RuntimeError('Not enough free disk space')
    if info['installed']:
        emit(stage='installed', **info)
        return
    stage = ROOT / (REVISION + '.partial')
    # Only remove our fixed, versioned staging directory.
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    log = ROOT / 'install.log'
    try:
        runtime = stage / 'runtime'
        emit(stage='source', message='Fetching pinned BitNet source')
        run(['git', 'init', str(runtime)], ROOT, log)
        run(['git', 'remote', 'add', 'origin', MANIFEST['runtimeRepo']], runtime, log)
        run(['git', 'fetch', '--depth', '1', 'origin', MANIFEST['runtimeRevision']], runtime, log)
        run(['git', 'checkout', '--detach', 'FETCH_HEAD'], runtime, log)
        run(['git', 'submodule', 'update', '--init', '--recursive', '--depth', '1'], runtime, log)
        emit(stage='build', message='Building the CPU inference runtime')
        build_runtime(runtime, log)
        if not reuse_model(stage / MANIFEST['modelFile']):
            emit(stage='download', bytes=0, total=MANIFEST['modelBytes'])
            download(stage / MANIFEST['modelFile'])
        emit(stage='verify', message='Starting model for a health check')
        serve(stage, once=True)
        (stage / 'ready.json').write_text(json.dumps(MANIFEST, indent=2))
        stage.rename(ACTIVE)
        # Earlier revisions are superseded once this one is verified.
        for other in revision_dirs():
            if other != ACTIVE:
                shutil.rmtree(other)
        emit(stage='installed', **preflight())
    finally:
        stop_child()
        if stage.exists():
            shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'install', 'serve', 'uninstall'])
    action = parser.parse_args().action
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, terminate)
    try:
        if action == 'status':
            info = preflight()
            info['diskBytes'] = sum(p.stat().st_size for p in ACTIVE.rglob('*') if p.is_file()) if ACTIVE.exists() else 0
            emit(stage='status', **info)
            return 0
        ROOT.mkdir(parents=True, exist_ok=True)
        with (ROOT / '.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if action == 'install':
                install()
            elif action == 'uninstall':
                for installed in revision_dirs():
                    shutil.rmtree(installed)
                emit(stage='removed', **preflight())
            else:
                if not (ACTIVE / 'ready.json').exists():
                    raise RuntimeError('Install the managed model first')
                serve(ACTIVE)
    except KeyboardInterrupt:
        emit(stage='cancelled')
        return 130
    except Exception as error:
        emit(stage='error', error=str(error))
        return 1
    finally:
        stop_child()
    return 0


if __name__ == '__main__':
    sys.exit(main())
