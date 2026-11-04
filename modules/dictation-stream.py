"""Record the mic, transcribe while the user speaks, then clean up the text.

Usage: dictate-stream CONFIG WAV OUT

Records 16 kHz mono via pw-record until SIGINT / SIGTERM and archives it to
WAV.  Meanwhile:
- Every pause of 12 s+ of audio commits a chunk, transcribed right away.
- Every shorter pause transcribes the pending audio speculatively: if the
  recording stops before more speech arrives, that text is used as is, so
  stopping after a pause leaves nothing to transcribe.
- The first transcription of 3 s+ fixes the language for the rest.
- Copilot starts with the recording, so its startup overlaps the speech.
- No speech after 4 s warns; none after 30 s stops the recording.
The notification shows the text so far.  On stop, OUT.raw gets the joined
transcript (non-speech markers and `replacements` fixed) and OUT.clean the
cleaned-up text (empty if cleanup failed).  If a chunk fails, the whole
recording is transcribed in one go; if that fails too, nothing is written.

Measured on the Arc iGPU and kept simple on purpose:
- whisper-server was slower per chunk (2.8 s) than whisper-cli (1.9 s, model
  load included), so there is no long-running server.
- A smaller audio context (-ac) halves short chunks but makes whisper loop
  ("for example x for example") on ~3 s ones.
- Chunks under ~12 s break sentences at hesitations; longer ones transcribe
  as well as the whole file.
- Language detection costs a second encoder pass (~1.3 s) per chunk.
"""

import array
import glob
import json
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import wave

RATE = 16000
FRAME = RATE * 30 // 1000  # samples per 30 ms analysis frame
MIN_CHUNK = 12000 // 30  # frames; shorter chunks lose context
MAX_CHUNK = 25000 // 30  # whisper sees 30 s windows; cut before that
PAUSE = 700 // 30  # frames of silence that end a chunk
MIN_SPEECH = 300 // 30  # loud frames a chunk needs, else it's skipped
LANG_MIN = 3000 // 30  # frames of audio before a detected language counts
NOISE_WINDOW = 10000 // 30  # frames used to estimate the noise floor
WARN_SILENT = 4000 // 30  # no speech this long: warn
STOP_SILENT = 30000 // 30  # no speech this long: stop


def log(msg):
    print(f"{time.strftime('%F %T')} {msg}", file=sys.stderr, flush=True)


def notify(body, ms=0):
    subprocess.run(
        ["notify-send", "-t", str(ms), "-h", "string:x-dunst-stack-tag:dictate",
         "Dictation", body],
        check=False, stderr=subprocess.DEVNULL)


def rms(frame):
    samples = array.array("h", frame)
    return (sum(s * s for s in samples) / max(len(samples), 1)) ** 0.5


def thresholds(levels):
    """(quiet, loud) rms levels, relative to the recent noise floor."""
    recent = sorted(levels[-NOISE_WINDOW:])
    # Capped: talking from the first second would otherwise count as noise.
    noise = min(recent[len(recent) // 5], 150.0)
    return max(150.0, 3 * noise), max(500.0, 6 * noise)


def wav_bytes(pcm):
    header = bytearray(b"RIFF")
    header += (36 + len(pcm)).to_bytes(4, "little") + b"WAVEfmt "
    header += (16).to_bytes(4, "little") + (1).to_bytes(2, "little")
    header += (1).to_bytes(2, "little") + RATE.to_bytes(4, "little")
    header += (RATE * 2).to_bytes(4, "little") + (2).to_bytes(2, "little")
    header += (16).to_bytes(2, "little") + b"data"
    header += len(pcm).to_bytes(4, "little")
    return bytes(header) + pcm


def tidy(text, replacements):
    # Drop non-speech markers like [BLANK_AUDIO] / (Musik).
    text = re.sub(r"\[[^]]*\]|\([^)]*\)", "", text)
    for wrong, right in replacements.items():
        text = re.sub(rf"\b{re.escape(wrong)}\b", right, text, flags=re.I)
    return " ".join(text.split())


def write(path, text):
    with open(path + ".tmp", "w") as f:
        f.write(text + "\n")
    os.replace(path + ".tmp", path)


class Whisper:
    """whisper-cli, one job at a time; a running job can be killed."""

    def __init__(self, model, workdir):
        self.model = model
        self.base = os.path.join(workdir, f"chunk-{os.getpid()}")
        self.proc = None

    def run(self, pcm, prompt, language):
        """Returns (text, language); `language` "auto" detects it."""
        with open(self.base + ".wav", "wb") as f:
            f.write(wav_bytes(pcm))
        try:
            # -nfa: flash attention is ~2x slower on the Arc iGPU (Vulkan).
            self.proc = subprocess.Popen(
                ["whisper-cli", "-m", self.model, "-f", self.base + ".wav",
                 "-l", language, "-nfa", "-np", "--prompt", prompt,
                 "-oj", "-of", self.base],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if self.proc.wait(timeout=60) != 0:
                raise RuntimeError(f"whisper-cli exited {self.proc.returncode}")
            with open(self.base + ".json") as f:
                result = json.load(f)
        finally:
            for ext in (".wav", ".json"):
                if os.path.exists(self.base + ext):
                    os.remove(self.base + ext)
        text = " ".join(s["text"].strip() for s in result["transcription"])
        return text.strip(), result["result"]["language"]

    def kill(self):
        if self.proc and self.proc.poll() is None:
            self.proc.kill()


class Copilot:
    """Claude via Copilot CLI, started early so its startup overlaps speech."""

    def __init__(self, config, home):
        # Own COPILOT_HOME: skips your plugins/skills (faster, smaller prompt);
        # login comes from the keyring.  No tools: the transcript is just text.
        os.makedirs(home, exist_ok=True)
        self.home = home
        self.prompt = config["cleanupPrompt"].rstrip("\n")
        self.proc = subprocess.Popen(
            ["copilot", "-s", "--model", config["cleanupModel"],
             "--reasoning-effort", config["cleanupEffort"],
             "--no-custom-instructions", "--disable-builtin-mcps",
             "--available-tools", "", "--no-auto-update",
             "--output-format", "json"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, cwd=home, text=True,
            env={**os.environ, "COPILOT_HOME": home})

    def clean(self, transcript):
        """The cleaned text, or "" on failure / timeout."""
        answer = queue.Queue()

        def read():
            for line in self.proc.stdout:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get("type") == "assistant.message":
                    answer.put(event["data"]["content"])
                    return
            answer.put("")

        threading.Thread(target=read, daemon=True).start()
        try:
            self.proc.stdin.write(
                f"{self.prompt}\n<transcript>\n{transcript}\n</transcript>\n")
            self.proc.stdin.close()
            # The answer arrives ~1.5 s before copilot exits; don't wait.
            return answer.get(timeout=60)
        except (OSError, queue.Empty):
            return ""
        finally:
            self.close()

    def close(self):
        self.proc.kill()
        self.proc.wait()
        # Every call leaves a session behind; there is no flag to disable that.
        for name in ("session-state", "logs"):
            shutil.rmtree(os.path.join(self.home, name), ignore_errors=True)
        for path in glob.glob(os.path.join(self.home, "session-store.db*")):
            os.remove(path)


def main():
    config_path, wav_path, out = sys.argv[1:4]
    with open(config_path) as f:
        config = json.load(f)
    workdir = os.path.dirname(os.path.abspath(out))
    begin = time.monotonic()

    rec = subprocess.Popen(
        ["pw-record", "--raw", "--rate", str(RATE), "--channels", "1",
         "--format", "s16", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    copilot = Copilot(config, os.path.join(workdir, "copilot"))
    whisper = Whisper(config["whisperModel"], workdir)

    # Stopping pw-record ends the read loop below once its output is drained.
    stopping = threading.Event()

    def stop(*_):
        stopping.set()
        rec.terminate()

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)

    archive = wave.open(wav_path, "wb")
    archive.setnchannels(1)
    archive.setsampwidth(2)
    archive.setframerate(RATE)

    audio = bytearray()  # whole recording, for cutting chunks
    levels = []  # rms per frame
    texts = []  # committed chunks
    spec = {}  # latest speculative result: start, end, text
    state = {"language": "auto", "failed": False, "running": None}
    # (kind, start frame, end frame); kind: commit, spec (speculative), final
    jobs = queue.Queue()

    def speech(start, end):
        _, loud = thresholds(levels)
        return sum(1 for lv in levels[start:end] if lv > loud)

    def preview(headline, extra=""):
        tail = " ".join(texts + [extra])[-300:].strip()
        notify(headline + ("\n\n…" + tail if tail else ""))

    def worker():
        while (job := jobs.get()) is not None:
            kind, start, end = job
            if kind == "spec" and speech(end, len(levels)) >= MIN_SPEECH:
                continue  # speech went on; a later job covers this audio
            reuse = spec.get("start") == start
            if kind == "final" and reuse and speech(spec["end"], end) < MIN_SPEECH:
                texts.append(spec["text"])  # stopped during / after a pause
                log(f"final chunk {start * 0.03:.1f}s-: speculative result")
                continue
            # Vocabulary plus the previous text, so a chunk continues the
            # sentence instead of starting fresh.
            prompt = f"{config['vocab']}. {' '.join(texts)[-200:]}"
            t = time.monotonic()
            state["running"] = job
            try:
                text, language = whisper.run(
                    bytes(audio[start * FRAME * 2:end * FRAME * 2]), prompt,
                    state["language"])
            except Exception as e:
                if kind != "spec":
                    log(f"{kind} chunk failed: {e}")
                    state["failed"] = True
                continue
            finally:
                state["running"] = None
            log(f"{kind} chunk {start * 0.03:.1f}-{end * 0.03:.1f}s "
                f"({language}) in {time.monotonic() - t:.1f}s")
            if end - start >= LANG_MIN:
                state["language"] = language
            if kind == "spec":
                spec.update(start=start, end=end, text=text)
                if not stopping.is_set():
                    preview("🎙 Recording… press Super+X again to stop", text)
            elif text:
                texts.append(text)
                if not stopping.is_set():
                    preview("🎙 Recording… press Super+X again to stop")

    thread = threading.Thread(target=worker)
    thread.start()

    start = 0  # first frame of the current chunk
    silence = 0  # consecutive quiet frames
    heard = 0  # loud frames so far
    warned = False
    gave_up = False
    asked = {}  # chunk start -> end of its latest speculative job

    def cut(end):
        nonlocal start
        if speech(start, end) >= MIN_SPEECH:
            jobs.put(("commit", start, end))
        start = end

    pending = b""
    while True:
        data = rec.stdout.read1(FRAME * 2) if rec.stdout else b""
        if not data:
            break
        archive.writeframesraw(data)
        pending += data
        while len(pending) >= FRAME * 2:
            frame, pending = pending[:FRAME * 2], pending[FRAME * 2:]
            audio += frame
            levels.append(rms(frame))
            quiet, loud = thresholds(levels)
            heard += levels[-1] > loud
            silence = silence + 1 if levels[-1] < quiet else 0
            length = len(levels) - start
            if length >= MIN_CHUNK and silence >= PAUSE:
                cut(len(levels) - silence // 2)  # middle of the pause
            elif length >= MAX_CHUNK:
                # No pause for 25 s: cut at the quietest frame of the last 5.
                tail = range(len(levels) - 5000 // 30, len(levels))
                cut(min(tail, key=lambda i: levels[i]) + 1)
            elif silence == PAUSE and speech(start, len(levels)) >= MIN_SPEECH:
                # Skipped if nothing was said since the last one.
                since = asked.get(start, start)
                if speech(since, len(levels)) >= MIN_SPEECH:
                    asked[start] = len(levels)
                    jobs.put(("spec", start, len(levels)))

            if heard < MIN_SPEECH:
                if len(levels) == WARN_SILENT:
                    warned = True
                    notify("🎙 Recording… no speech detected — is the mic "
                           "muted?  Press Super+X to stop")
                elif len(levels) == STOP_SILENT and not stopping.is_set():
                    gave_up = True
                    stop()
            elif warned:
                warned = False
                preview("🎙 Recording… press Super+X again to stop")
    rec.wait()
    archive.close()

    if gave_up:
        jobs.put(None)
        thread.join()
        copilot.close()
        os.remove(wav_path)
        notify("Stopped — no speech for 30 s", 5000)
        log("stopped: no speech")
        return

    stopped = time.monotonic()
    preview("Transcribing…", spec.get("text", ""))
    running = state["running"]
    if running and speech(running[2], len(levels)) >= MIN_SPEECH:
        whisper.kill()  # outdated speculative job, don't wait for it
    if speech(start, len(levels)) >= MIN_SPEECH:
        jobs.put(("final", start, len(levels)))
    jobs.put(None)
    thread.join()

    if state["failed"]:
        log("chunk failed, transcribing the whole recording")
        try:
            text, _ = whisper.run(bytes(audio), f"{config['vocab']}.", "auto")
        except Exception as e:
            log(f"whole recording failed: {e}")
            copilot.close()
            sys.exit(1)
        texts[:] = [text]

    raw = tidy(" ".join(texts), config["replacements"])
    write(out + ".raw", raw)
    transcribed = time.monotonic()
    if not raw:
        copilot.close()
        return
    notify("Cleaning up…", 60000)
    write(out + ".clean", copilot.clean(raw))
    log(f"{len(levels) * 0.03:.1f}s recording; after stop: transcribe "
        f"{transcribed - stopped:.1f}s, cleanup "
        f"{time.monotonic() - transcribed:.1f}s; total "
        f"{time.monotonic() - begin:.1f}s")


if __name__ == "__main__":
    main()
