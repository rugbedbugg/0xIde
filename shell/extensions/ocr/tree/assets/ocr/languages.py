#!/usr/bin/env python3
"""Manage Arch's OCR language packages through its normal administrator prompt."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

PACMAN = '/usr/bin/pacman'
PKEXEC = '/usr/bin/pkexec'
PREFIX = 'tesseract-data-'
CODE = re.compile(r'[a-z]{3}(?:_[a-z0-9]+)*')
ISO_CODES = Path('/usr/share/iso-codes/json/iso_639-3.json')


def emit(**data):
    print(json.dumps(data), flush=True)


def query(*args):
    result = subprocess.run([PACMAN, *args], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'Could not read the package list')
    return result.stdout.splitlines()


def codes(packages):
    return sorted({p[len(PREFIX):] for p in packages
                   if p.startswith(PREFIX) and CODE.fullmatch(p[len(PREFIX):])
                   and p != PREFIX + 'osd'})


def names():
    # Name lookup is optional; package codes always work without iso-codes.
    result = {c: {'name': n, 'aliases': [a]} for c, n, a in (
        ('eng', 'English', 'en'), ('deu', 'German', 'de'),
        ('fra', 'French', 'fr'), ('afr', 'Afrikaans', 'af'))}
    try:
        for entry in json.loads(ISO_CODES.read_text())['639-3']:
            result[entry['alpha_3']] = {
                'name': entry['name'],
                'aliases': [entry[k] for k in ('alpha_2', 'bibliographic') if k in entry],
            }
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return result


def catalogue():
    if not shutil.which(PACMAN):
        raise ValueError('Language management requires Arch Linux and pacman')
    labels = names()
    available = codes(query('-Slq'))
    installed = codes(query('-Qq'))
    return {'available': [dict(code=c, **labels.get(c, {'name': c, 'aliases': []}))
                          for c in sorted(set(available + installed))],
            'installable': available, 'installed': installed}


def resolve(value, languages):
    wanted = value.strip().casefold()
    for language in languages:
        if wanted in [s.casefold() for s in
                      [language['code'], language['name'], *language['aliases']]]:
            return language['code']
    raise ValueError(f'No OCR language named "{value.strip()}"')


def change(action, value):
    if action not in ('install', 'remove'):
        raise ValueError('Unknown language action')
    data = catalogue()
    code = resolve(value, data['available'])
    # Even a malformed catalogue cannot add arguments or select another package.
    if not CODE.fullmatch(code) or code == 'osd':
        raise ValueError('Invalid OCR language code')
    if action == 'install':
        if code in data['installed']:
            return f'{code} is already installed'
        if code not in data['installable']:
            raise ValueError(f'No package available for {code}')
        args = ['-S', '--needed', '--noconfirm', '--', PREFIX + code]
    else:
        if code not in data['installed']:
            raise ValueError(f'{code} is not installed as a language package')
        if len(data['installed']) < 2:
            raise ValueError('Keep at least one OCR language installed')
        # No recursive removal or dependency overrides: pacman must preserve
        # Tesseract and every other package that needs this language.
        args = ['-R', '--noconfirm', '--', PREFIX + code]
    if not shutil.which(PKEXEC):
        raise ValueError('Install polkit to manage OCR languages')
    emit(stage=action, code=code)
    # Only pacman runs as root. This helper and all name resolution stay under
    # the user account; no passwordless rule or privileged script is installed.
    result = subprocess.run([PKEXEC, PACMAN, *args], capture_output=True, text=True)
    if result.returncode == 126:
        raise ValueError('Administrator approval was cancelled')
    if result.returncode == 127:
        raise ValueError('Administrator approval failed')
    if result.returncode:
        raise ValueError((result.stderr.strip() or result.stdout.strip()
                          or f'Could not {action} {code}')[-1200:])
    installed = codes(query('-Qq'))
    if (code in installed) != (action == 'install'):
        raise ValueError(f'Could not verify the package change for {code}')
    return f'{"Installed" if action == "install" else "Removed"} {code}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('status', 'install', 'remove'))
    parser.add_argument('language', nargs='?', default='')
    args = parser.parse_args()
    try:
        if args.action == 'status':
            emit(**catalogue())
        else:
            emit(message=change(args.action, args.language))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        emit(error=str(error))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
