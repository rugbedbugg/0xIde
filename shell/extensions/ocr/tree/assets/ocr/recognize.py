#!/usr/bin/env python3
"""Tesseract adapter. Emits one JSON object; keeps image coordinates for tables."""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile

# Screen text is around 96 DPI; Tesseract is trained on scans near 300. Reading
# a copy three times the size fixes most misread letters and punctuation.
SCALE = 3


def upscaled(path):
    """A grey, SCALE-times larger copy of the capture, or None without magick."""
    if not shutil.which('magick'):
        return None
    handle, copy = tempfile.mkstemp(suffix='.png', prefix='0xide-ocr.')
    os.close(handle)
    try:
        subprocess.run(['magick', path, '-colorspace', 'Gray', '-resize', f'{SCALE * 100}%', copy],
                       check=True, capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        os.unlink(copy)
        return None
    return copy


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
    if not shutil.which('tesseract'):
        raise ValueError('OCR requires Tesseract. Install tesseract first.')
    missing = sorted(set(language.split('+')) - set(languages()))
    if missing:
        raise ValueError(f"Tesseract has no data for {', '.join(missing)}. "
                         f"Install it (e.g. tesseract-data-{missing[0]}) or change the OCR languages.")
    copy = upscaled(path)
    scale = SCALE if copy else 1
    try:
        # TSV contains every occurrence; never key text by its value or deduplicate.
        command = ['tesseract', copy or path, '-', '-l', language, '--psm', '6', '-c', 'preserve_interword_spaces=1', 'tsv']
        result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=120)
    finally:
        if copy:
            os.unlink(copy)
    # Word boxes are reported in the original capture's pixels, which is what
    # the table's column boundaries are measured in.
    words = [w | {k: round(w[k] / scale) for k in ('left', 'top', 'width', 'height')}
             for w in words_from_tsv(result.stdout)]
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
