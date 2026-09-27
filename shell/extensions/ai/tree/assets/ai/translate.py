#!/usr/bin/env python3
"""Offline translation with Argos Translate models. JSON line events.

    translate.py status
    translate.py install <lang>     both directions through the pivot language
    translate.py remove <lang>
    translate.py translate <from> <to> <text>   plain text to stdout

Argos's .argosmodel packages are zips holding a CTranslate2 model and a
SentencePiece model. Those two packages are all it takes to run them; the
argostranslate library would add stanza, spacy and PyTorch only to split
sentences, which a regular expression does well enough for OCR'd text.
"""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import sys
import urllib.request
import zipfile

MANIFEST = json.loads(Path(__file__).with_name('translate.json').read_text())
PIVOT = MANIFEST['index']['pivot']
ROOT = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / '0xide/translate'
AGENT = {'User-Agent': '0xide-translate/1'}
# Split after sentence punctuation, keeping it with its sentence.
SENTENCE = re.compile(r'(?<=[.!?。！？])\s+')


def emit(**data):
    print(json.dumps(data), flush=True)


def fetch(url):
    request = urllib.request.Request(url, headers=AGENT)
    return urllib.request.urlopen(request, timeout=60)


def index():
    """The pinned package index, cached so status works offline."""
    cache = ROOT / 'index.json'
    try:
        with fetch(MANIFEST['index']['url']) as response:
            data = response.read()
        ROOT.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(data)
    except OSError:
        if not cache.is_file():
            raise
        data = cache.read_bytes()
    return [p for p in json.loads(data) if p.get('links')]


def pair_dir(source, target):
    return ROOT / f'{source}_{target}'


def installed():
    languages = set()
    for path in ROOT.glob('*_*'):
        if path.is_dir() and (path / 'model/model.bin').is_file():
            source, _, target = path.name.partition('_')
            languages.update((source, target))
    return sorted(languages)


def status():
    try:
        packages = index()
    except OSError as error:
        emit(stage='status', installed=installed(), available=[], error=f'Could not load the language list: {error}')
        return
    # A language can be installed when the index has it in both directions
    # through the pivot, which is what makes any installed pair reachable.
    names, directions = {}, set()
    for p in packages:
        names[p['from_code']] = p['from_name']
        names[p['to_code']] = p['to_name']
        directions.add((p['from_code'], p['to_code']))
    available = [{'code': code, 'name': names[code]} for code in sorted(names, key=names.get)
                 if code == PIVOT or ((PIVOT, code) in directions and (code, PIVOT) in directions)]
    emit(stage='status', installed=installed(), available=available)


def install_pair(package):
    destination = pair_dir(package['from_code'], package['to_code'])
    if (destination / 'model/model.bin').is_file():
        return
    partial = destination.with_name(destination.name + '.partial')
    shutil.rmtree(partial, ignore_errors=True)
    partial.mkdir(parents=True)
    archive = partial / 'package.zip'
    limit = MANIFEST['limits']['modelBytes']
    with fetch(package['links'][0]) as response, archive.open('wb') as output:
        total = int(response.headers.get('Content-Length') or 0)
        if total > limit:
            raise RuntimeError(f"{package['code']} is larger than {limit} bytes")
        count = 0
        while block := response.read(1024 * 1024):
            count += len(block)
            if count > limit:
                raise RuntimeError(f"{package['code']} is larger than {limit} bytes")
            output.write(block)
            emit(stage='download', package=package['code'], bytes=count, total=total)
    if total and count != total:
        raise RuntimeError(f"{package['code']} download was cut short")
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise RuntimeError(f"{package['code']} is corrupt")
        for member in bundle.infolist():
            # One top-level directory; stanza is only for sentence splitting.
            parts = Path(member.filename).parts[1:]
            if not parts or parts[0] == 'stanza' or '..' in parts or member.is_dir():
                continue
            target = partial.joinpath(*parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(member) as src, target.open('wb') as dst:
                shutil.copyfileobj(src, dst)
    archive.unlink()
    if not (partial / 'model/model.bin').is_file() or not (partial / 'sentencepiece.model').is_file():
        raise RuntimeError(f"{package['code']} is not a translation model")
    shutil.rmtree(destination, ignore_errors=True)
    partial.rename(destination)


def install(language):
    if language == PIVOT:
        raise RuntimeError(f'{PIVOT} is always available once any language is installed')
    packages = {(p['from_code'], p['to_code']): p for p in index()}
    wanted = [(PIVOT, language), (language, PIVOT)]
    missing = [pair for pair in wanted if pair not in packages]
    if missing:
        raise RuntimeError(f'No translation model for {language}')
    for pair in wanted:
        install_pair(packages[pair])
    emit(stage='installed', installed=installed())


def remove(language):
    for path in ROOT.glob('*_*'):
        if language in path.name.removesuffix('.partial').split('_'):
            shutil.rmtree(path)
    emit(stage='removed', installed=installed())


def route(source, target):
    """The chain of installed pairs from source to target, or None."""
    if source == target:
        return []
    if (pair_dir(source, target) / 'model/model.bin').is_file():
        return [(source, target)]
    via = [(source, PIVOT), (PIVOT, target)]
    if all((pair_dir(*pair) / 'model/model.bin').is_file() for pair in via):
        return via
    return None


def translate(source, target, text):
    chain = route(source, target)
    if chain is None:
        raise RuntimeError(f'Install {source} and {target} in the translation settings first')
    if chain and 'ctranslate2' not in sys.modules:
        try:
            import ctranslate2  # noqa: F401
            import sentencepiece  # noqa: F401
        except ImportError:
            # Run again with the pinned packages, in uv's cached environment.
            if os.environ.get('OXIDE_TRANSLATE_REEXEC'):
                raise
            os.environ['OXIDE_TRANSLATE_REEXEC'] = '1'
            command = ['uv', 'run', '--no-project', '--python', MANIFEST['runtime']['python']]
            for package in MANIFEST['runtime']['packages']:
                command += ['--with', package]
            os.execvp('uv', command + ['python', __file__, 'translate', source, target, text])
    for pair in chain:
        text = translate_pair(pair, text)
    sys.stdout.write(text)
    sys.stdout.flush()


def translate_pair(pair, text):
    import ctranslate2
    import sentencepiece

    directory = pair_dir(*pair)
    tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(directory / 'sentencepiece.model'))
    translator = ctranslate2.Translator(str(directory / 'model'), device='cpu')
    lines = text.split('\n')
    # Line breaks are kept: OCR'd text is often a list or a table.
    sentences = [[s for s in SENTENCE.split(line.strip()) if s] for line in lines]
    flat = [s for group in sentences for s in group]
    results = translator.translate_batch([tokenizer.encode(s, out_type=str) for s in flat], beam_size=2) if flat else []
    decoded = iter(''.join(r.hypotheses[0]).replace('▁', ' ').strip() for r in results)
    return '\n'.join(' '.join(next(decoded) for _ in group) for group in sentences)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ('status', 'install', 'remove', 'translate'):
        print(__doc__, file=sys.stderr)
        return 2
    action, args = sys.argv[1], sys.argv[2:]
    try:
        if action == 'status':
            status()
        elif action == 'translate':
            translate(*args[:3])
        else:
            ROOT.mkdir(parents=True, exist_ok=True)
            with (ROOT / '.lock').open('w') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError('Another language is being installed or removed') from None
                install(args[0]) if action == 'install' else remove(args[0])
    except KeyboardInterrupt:
        emit(stage='cancelled')
        return 130
    except Exception as error:
        if action == 'translate':
            print(str(error), file=sys.stderr)
        else:
            emit(stage='error', error=str(error))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
