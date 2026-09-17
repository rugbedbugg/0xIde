#!/usr/bin/env python3
"""Tesseract adapter. Emits one JSON object; keeps image coordinates for tables."""
from __future__ import annotations

import argparse
import csv
import io
import json
import statistics
import subprocess
import sys


def languages():
    result = subprocess.run(['tesseract', '--list-langs'], capture_output=True, text=True, check=True, timeout=10)
    return [line.strip() for line in result.stdout.splitlines()[1:] if line.strip() != 'osd']


def words_from_tsv(text):
    words = []
    for row in csv.DictReader(io.StringIO(text), delimiter='\t', quoting=csv.QUOTE_NONE):
        if row.get('level') == '5' and row.get('text', '').strip():
            words.append({key: int(row[key]) for key in ('left', 'top', 'width', 'height')} | {'text': row['text']})
    return words


def table_from_words(words, boundaries=None):
    if not words:
        return {'rows': [], 'boundaries': [], 'lines': []}
    height = statistics.median(w['height'] for w in words)
    lines = []
    for word in sorted(words, key=lambda w: (w['top'] + w['height'] / 2, w['left'])):
        center = word['top'] + word['height'] / 2
        line = next((line for line in reversed(lines) if abs(line['center'] - center) <= height * .6), None)
        if line is None:
            line = {'center': center, 'words': []}
            lines.append(line)
        line['words'].append(word)
    groups = []
    for line in lines:
        row = []
        for word in sorted(line['words'], key=lambda w: w['left']):
            if row and word['left'] - row[-1]['right'] < height * 1.5:
                row[-1]['text'] += ' ' + word['text']
                row[-1]['right'] = word['left'] + word['width']
            else:
                row.append({'left': word['left'], 'right': word['left'] + word['width'], 'text': word['text']})
        groups.append(row)
    if boundaries is None:
        # The fullest row supplies initial column anchors. Users can correct
        # boundaries for spanning headers, wrapped cells or unusual alignment.
        anchors = max(groups, key=len)
        boundaries = [(a['right'] + b['left']) / 2 for a, b in zip(anchors, anchors[1:])]
    rows = []
    for groups_row in groups:
        cells = [''] * (len(boundaries) + 1)
        for group in groups_row:
            col = sum(group['left'] >= boundary for boundary in boundaries)
            cells[col] = (cells[col] + ' ' + group['text']).strip()
        rows.append(cells)
    return {'rows': rows, 'boundaries': boundaries,
            'lines': [sorted(line['words'], key=lambda word: word['left']) for line in lines]}


def recognize(path, language):
    missing = set(language.split('+')) - set(languages())
    if missing:
        raise ValueError('Missing Tesseract language data: ' + ', '.join(sorted(missing)))
    # TSV contains every occurrence; never key text by its value or deduplicate.
    command = ['tesseract', path, '-', '-l', language, '--psm', '6', '-c', 'preserve_interword_spaces=1', 'tsv']
    result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=120)
    words = words_from_tsv(result.stdout)
    table = table_from_words(words)
    return {'words': words, **table, 'text': '\n'.join('    '.join(row) for row in table['rows'])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('image', nargs='?')
    parser.add_argument('--language', default='eng')
    parser.add_argument('--languages', action='store_true')
    args = parser.parse_args()
    try:
        data = {'languages': languages()} if args.languages else recognize(args.image, args.language)
        print(json.dumps(data))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(json.dumps({'error': detail or str(error)}))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
