#!/usr/bin/env python3
"""Voice dictation: the whisper.cpp model, and the listener that types.

    speech.py status | install | remove       JSON line events
    speech.py listen [--language CODE]        runs until SIGTERM

listen keeps whisper-server running with the model loaded, reads the
microphone as a raw stream, and cuts it into phrases at pauses, judging speech
by its loudness over the room's own background level. Each phrase is sent to
the server and its text typed into the focused window, so dictation keeps up
with the speaker instead of waiting for the end.

The engine is the distribution's whisper-cpp; only the model is fetched here,
pinned by revision and verified by SHA-256, as manifests/speech.toml says.
"""
from __future__ import annotations

import array
import fcntl
import hashlib
import io
import json
import math
import os
from pathlib import Path
import queue
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
import wave

MANIFEST = json.loads(Path(__file__).with_name('speech.json').read_text())['model']
ROOT = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / '0xide/speech'
MODEL = ROOT / MANIFEST['file']


def emit(**data):
    print(json.dumps(data), flush=True)


def status():
    missing = [tool for tool in ('whisper-server', 'pw-record', 'wtype') if not shutil.which(tool)]
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


# --- listening ---------------------------------------------------------------

RATE = 16000
FRAME = RATE * 30 // 1000          # 30 ms of samples
START_FRAMES = 3                   # this much loud audio starts a phrase
END_FRAMES = 25                    # this much quiet (750 ms) ends it
PREROLL = 10                       # kept from before the start, so no clipped first word
MIN_VOICED = 8                     # under 240 ms of sound is a click, not a word
MAX_FRAMES = 20 * 1000 // 30       # a phrase is cut at 20 s regardless
# Whisper's usual output for noise or silence, never worth typing.
NOISE = {'', 'you', 'thank you.', 'thanks for watching!', '.', '[blank_audio]', '(silence)', '[silence]'}


def level(frame):
    """Loudness of 16-bit samples in dBFS."""
    samples = array.array('h', frame)
    if not samples:
        return -100.0
    power = sum(s * s for s in samples) / len(samples)
    return 10 * math.log10(power / 32768 ** 2) if power else -100.0


class Segmenter:
    """Cuts a stream of frames into phrases, relative to the background level."""

    def __init__(self):
        self.floor = -60.0
        self.peak = -100.0
        self.frames, self.preroll = [], []
        self.loud = self.quiet = self.voiced = 0

    def push(self, frame):
        """Returns a finished phrase as bytes, or None."""
        db = level(frame)
        if not self.frames:
            # The background level follows the room while nobody speaks. It is
            # held above digital silence, which no microphone really produces
            # and which would make ordinary room noise look like speech.
            if db < self.floor + 6:
                self.floor = max(-70.0, 0.9 * self.floor + 0.1 * db)
            else:
                self.floor += 0.02
            self.preroll = (self.preroll + [frame])[-PREROLL:]
            self.loud = self.loud + 1 if db > max(self.floor + 12, -50) else 0
            if self.loud >= START_FRAMES:
                self.frames, self.preroll, self.quiet, self.peak = self.preroll, [], 0, db
                self.voiced = self.loud
            return None
        self.frames.append(frame)
        self.peak = max(self.peak, db)
        # A pause is near the background, or far below the phrase itself.
        if db < max(self.floor + 6, self.peak - 30):
            self.quiet += 1
        else:
            self.quiet = 0
            self.voiced += 1
        if self.quiet >= END_FRAMES or len(self.frames) >= MAX_FRAMES:
            return self.flush()
        return None

    def flush(self):
        frames, voiced = self.frames, self.voiced
        self.frames, self.loud, self.voiced = [], 0, 0
        return b''.join(frames) if voiced >= MIN_VOICED else None


def as_wav(pcm):
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm)
    return buffer.getvalue()


def transcribe(port, pcm):
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="phrase.wav"\r\n'
        'Content-Type: audio/wav\r\n\r\n'.encode() + as_wav(pcm) + b'\r\n',
        f'--{boundary}\r\nContent-Disposition: form-data; name="response_format"\r\n\r\njson\r\n'.encode(),
        f'--{boundary}\r\nContent-Disposition: form-data; name="temperature"\r\n\r\n0\r\n'.encode(),
        f'--{boundary}--\r\n'.encode(),
    ]
    request = urllib.request.Request(f'http://127.0.0.1:{port}/inference', data=b''.join(parts),
                                     headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read()).get('text', '')


def clean(text):
    text = ' '.join(text.split())
    if text.lower() in NOISE or (text[:1] in '[(' and text[-1:] in '])'):
        return ''
    return text


class Typist:
    """Types each phrase, with a space between phrases."""

    def __init__(self):
        self.typed = False

    def type(self, text):
        if self.typed and text[:1] not in '.,!?;:':
            text = ' ' + text
        subprocess.run(['wtype', '--', text], check=False)
        self.typed = True


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def listen(language):
    if not status()['installed']:
        raise RuntimeError('Install the speech model first')
    port = free_port()
    threads = str(max(1, min(4, (os.cpu_count() or 2) // 2)))
    log = (ROOT / 'server.log').open('w')
    server = subprocess.Popen(['whisper-server', '-m', str(MODEL), '--host', '127.0.0.1', '--port', str(port),
                               '-l', language, '-t', threads, '-nth', '0.6'],
                              stdout=log, stderr=log, start_new_session=True)
    recorder = None
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    try:
        for _ in range(120):
            if server.poll() is not None:
                raise RuntimeError(f'whisper-server exited; see {ROOT / "server.log"}')
            try:
                socket.create_connection(('127.0.0.1', port), timeout=1).close()
                break
            except OSError:
                time.sleep(0.25)
        else:
            raise RuntimeError('whisper-server did not start')

        phrases = queue.Queue()
        typist = Typist()

        def worker():
            while (pcm := phrases.get()) is not None:
                try:
                    text = clean(transcribe(port, pcm))
                except OSError as error:
                    emit(stage='error', error=str(error))
                    continue
                if text:
                    typist.type(text)
                    emit(stage='typed', text=text)

        typing = threading.Thread(target=worker, daemon=True)
        typing.start()
        recorder = subprocess.Popen(['pw-record', '--rate', str(RATE), '--channels', '1', '--format', 's16',
                                     '--raw', '-'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        emit(stage='listening')
        segmenter = Segmenter()
        while not stopping.is_set():
            frame = recorder.stdout.read(FRAME * 2)
            if not frame:
                break
            if (pcm := segmenter.push(frame)) is not None:
                phrases.put(pcm)
        # Whatever was being said when dictation was turned off still counts.
        if (pcm := segmenter.flush()) is not None:
            phrases.put(pcm)
        phrases.put(None)
        typing.join(timeout=60)
    finally:
        for child in (recorder, server):
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
        log.close()
    emit(stage='stopped')


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ''
    if action not in ('status', 'install', 'remove', 'listen'):
        print(__doc__, file=sys.stderr)
        return 2
    if action == 'listen':
        language = sys.argv[3] if sys.argv[2:3] == ['--language'] and len(sys.argv) > 3 else 'auto'
        try:
            listen(language)
        except Exception as error:
            emit(stage='error', error=str(error))
            return 1
        return 0
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
