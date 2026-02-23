from __future__ import annotations

import queue
import sys
import threading
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import numpy as np


@dataclass(frozen=True)
class AudioFormat:
    sample_rate_hz: int
    channels: int


PCM16_16KHZ_MONO = AudioFormat(sample_rate_hz=16_000, channels=1)


def pcm16_bytes_from_ndarray(audio_i16: np.ndarray) -> bytes:
    if audio_i16.dtype != np.int16:
        raise ValueError(f"expected int16, got {audio_i16.dtype}")
    return audio_i16.tobytes(order="C")


def write_wav_pcm16(path: str | Path, *, pcm16: bytes, fmt: AudioFormat) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(fmt.channels)
        wf.setsampwidth(2)  # int16
        wf.setframerate(fmt.sample_rate_hz)
        wf.writeframes(pcm16)


def play_pcm16(*, pcm16: bytes, fmt: AudioFormat) -> None:
    import sounddevice as sd  # imported lazily

    audio = np.frombuffer(pcm16, dtype=np.int16)
    if fmt.channels > 1:
        audio = audio.reshape((-1, fmt.channels))

    sd.play(audio, samplerate=fmt.sample_rate_hz)
    sd.wait()


class MicStreamer:
    """Stream microphone audio as PCM16 chunks.

    - Uses sounddevice callback to avoid blocking.
    - Produces fixed-size chunks (frame_count per callback).
    """

    def __init__(
        self,
        *,
        fmt: AudioFormat = PCM16_16KHZ_MONO,
        chunk_ms: int = 100,
        device: int | None = None,
    ) -> None:
        self._fmt = fmt
        self._chunk_ms = chunk_ms
        self._device = device

        self._q: "queue.Queue[bytes]" = queue.Queue()
        self._stop = threading.Event()

    @property
    def fmt(self) -> AudioFormat:
        return self._fmt

    def iter_chunks(self) -> Iterator[bytes]:
        import sounddevice as sd  # lazy import

        frames_per_chunk = int(self._fmt.sample_rate_hz * (self._chunk_ms / 1000.0))
        if frames_per_chunk <= 0:
            raise ValueError("chunk_ms too small")

        def callback(indata: np.ndarray, _frames: int, _time, status) -> None:  # type: ignore[no-untyped-def]
            if status:
                # keep going; status is informative
                print(f"[mic] status: {status}", file=sys.stderr)
            if self._stop.is_set():
                return

            # sounddevice gives float32 by default; request int16.
            pcm16 = pcm16_bytes_from_ndarray(indata.copy())
            self._q.put(pcm16)

        stream = sd.InputStream(
            samplerate=self._fmt.sample_rate_hz,
            channels=self._fmt.channels,
            dtype="int16",
            blocksize=frames_per_chunk,
            device=self._device,
            callback=callback,
        )

        with stream:
            while not self._stop.is_set():
                try:
                    yield self._q.get(timeout=0.25)
                except queue.Empty:
                    continue

    def stop(self) -> None:
        self._stop.set()
