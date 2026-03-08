#!/usr/bin/env python3
"""stt_file_google.py — File to text using Google Cloud Speech-to-Text v2.

This is a tiny side prototype meant for quick comparisons.

It supports two modes:
- recognize: batch recognition (auto-decoding; works with many container formats)
- stream: streaming recognition by replaying a WAV file in chunks
          (STRICT: PCM16, 16kHz, mono WAV only)

Output:
- Transcript is printed to STDOUT (plain text only).
- Timing / diagnostics are printed to STDERR.

Credentials:
- Uses Application Default Credentials (ADC).

Config via env vars (defaults match the app's Python worker):
- GOOGLE_CLOUD_PROJECT (or VERTEXAI_PROJECT)
- STT_LOCATION (default: eu)
- STT_LANGUAGE_CODES (default: en-US)
- STT_MODEL (default: chirp_3)
- STT_RECOGNIZER_ID (default: _)
"""

from __future__ import annotations

import argparse
import os
import sys
import time
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, List, Optional

from google.api_core.client_options import ClientOptions
from google.cloud import speech_v2


def _env(name: str, default: Optional[str] = None) -> Optional[str]:
    v = os.environ.get(name)
    return v if v is not None and v.strip() != "" else default


def default_project_id() -> Optional[str]:
    return _env("GOOGLE_CLOUD_PROJECT") or _env("VERTEXAI_PROJECT")


def stt_location() -> str:
    return str(_env("STT_LOCATION", "eu"))


def stt_language_codes() -> List[str]:
    raw = str(_env("STT_LANGUAGE_CODES", "en-US"))
    codes = [c.strip() for c in raw.split(",") if c.strip()]
    return codes or ["en-US"]


def stt_model() -> str:
    return str(_env("STT_MODEL", "chirp_3"))


def stt_recognizer_id() -> str:
    return str(_env("STT_RECOGNIZER_ID", "_"))


def recognizer_resource(*, project_id: str, location: str, recognizer_id: str) -> str:
    parent = f"projects/{project_id}/locations/{location}"
    return f"{parent}/recognizers/{recognizer_id}"


def client_for_location(location: str) -> speech_v2.SpeechClient:
    return speech_v2.SpeechClient(
        client_options=ClientOptions(api_endpoint=f"{location}-speech.googleapis.com")
    )


def recognize_batch(*, client: speech_v2.SpeechClient, recognizer: str, audio_path: Path) -> str:
    content = audio_path.read_bytes()

    config = speech_v2.RecognitionConfig(
        auto_decoding_config=speech_v2.AutoDetectDecodingConfig(),
        language_codes=stt_language_codes(),
        model=stt_model(),
    )

    request = speech_v2.RecognizeRequest(
        recognizer=recognizer,
        config=config,
        content=content,
    )

    response = client.recognize(request=request)

    transcripts: List[str] = []
    for result in response.results:
        if result.alternatives:
            t = (result.alternatives[0].transcript or "").strip()
            if t:
                transcripts.append(t)

    return "\n".join(transcripts).strip()


@dataclass(frozen=True)
class WavPcm16:
    sample_rate_hz: int
    channels: int
    pcm16le: bytes


def read_wav_pcm16_mono_16khz(path: Path) -> WavPcm16:
    # wave module handles standard PCM WAV.
    with wave.open(str(path), "rb") as wf:
        channels = int(wf.getnchannels())
        sample_rate = int(wf.getframerate())
        sampwidth = int(wf.getsampwidth())
        comptype = wf.getcomptype()

        if comptype != "NONE":
            raise ValueError(f"WAV must be uncompressed PCM (comptype=NONE), got {comptype!r}")
        if channels != 1:
            raise ValueError(f"WAV must be mono (1 channel), got {channels}")
        if sample_rate != 16_000:
            raise ValueError(f"WAV must be 16kHz, got {sample_rate}Hz")
        if sampwidth != 2:
            raise ValueError(f"WAV must be PCM16 (sample width 2 bytes), got {sampwidth}")

        frames = wf.readframes(wf.getnframes())

    return WavPcm16(sample_rate_hz=sample_rate, channels=channels, pcm16le=frames)


def iter_pcm16_chunks(*, pcm16le: bytes, sample_rate_hz: int, chunk_ms: int) -> Iterator[bytes]:
    if chunk_ms <= 0:
        raise ValueError("chunk_ms must be > 0")

    bytes_per_sample = 2
    samples_per_chunk = int(sample_rate_hz * (chunk_ms / 1000.0))
    bytes_per_chunk = samples_per_chunk * bytes_per_sample

    if bytes_per_chunk <= 0:
        bytes_per_chunk = 3200  # ~100ms at 16kHz mono PCM16

    for i in range(0, len(pcm16le), bytes_per_chunk):
        yield pcm16le[i : i + bytes_per_chunk]


def recognize_streaming_replay(
    *,
    client: speech_v2.SpeechClient,
    recognizer: str,
    pcm16_chunks: Iterable[bytes],
    interim_results: bool = False,
) -> str:
    explicit = speech_v2.ExplicitDecodingConfig(
        encoding=speech_v2.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=16_000,
        audio_channel_count=1,
    )

    recognition_config = speech_v2.RecognitionConfig(
        explicit_decoding_config=explicit,
        language_codes=stt_language_codes(),
        model=stt_model(),
    )

    streaming_config = speech_v2.StreamingRecognitionConfig(
        config=recognition_config,
        streaming_features=speech_v2.StreamingRecognitionFeatures(
            interim_results=bool(interim_results),
        ),
    )

    def reqs() -> Iterator[speech_v2.StreamingRecognizeRequest]:
        yield speech_v2.StreamingRecognizeRequest(
            recognizer=recognizer,
            streaming_config=streaming_config,
        )
        for chunk in pcm16_chunks:
            if chunk:
                yield speech_v2.StreamingRecognizeRequest(audio=chunk)

    # Collect *final* segments only (plain transcript).
    final_segments: List[str] = []

    for resp in client.streaming_recognize(requests=reqs()):
        for result in resp.results:
            if not result.alternatives:
                continue
            text = (result.alternatives[0].transcript or "").strip()
            if not text:
                continue
            if result.is_final:
                final_segments.append(text)

    return " ".join(t for t in final_segments if t).strip()


def main() -> None:
    p = argparse.ArgumentParser(
        description="File STT using Google Cloud Speech-to-Text v2 (batch or streaming replay)."
    )
    p.add_argument("audio_path", help="Path to audio file (recognize: many formats; stream: WAV PCM16 16k mono)")
    p.add_argument(
        "--mode",
        choices=["recognize", "stream"],
        default="recognize",
        help="recognize=batch auto-decoding; stream=streaming replay (PCM16 16k mono WAV only)",
    )
    p.add_argument("--project", help="GCP project id (or set GOOGLE_CLOUD_PROJECT)")
    p.add_argument("--location", default=None, help="STT location (default: env STT_LOCATION or 'eu')")
    p.add_argument("--recognizer-id", default=None, help="Recognizer id (default: env STT_RECOGNIZER_ID or '_')")
    p.add_argument(
        "--chunk-ms",
        type=int,
        default=100,
        help="(stream mode) chunk size in milliseconds (default: 100)",
    )
    p.add_argument(
        "--interim",
        action="store_true",
        help="(stream mode) request interim results (does not change stdout; still prints final only)",
    )

    args = p.parse_args()

    project = args.project or default_project_id()
    if not project:
        print(
            "Error: set GOOGLE_CLOUD_PROJECT (or pass --project).", file=sys.stderr
        )
        raise SystemExit(2)

    location = args.location or stt_location()
    recognizer_id = args.recognizer_id or stt_recognizer_id()
    recognizer = recognizer_resource(project_id=project, location=location, recognizer_id=recognizer_id)

    audio_path = Path(args.audio_path)
    if not audio_path.exists():
        print(f"Error: file not found: {audio_path}", file=sys.stderr)
        raise SystemExit(2)

    client = client_for_location(location)

    t0 = time.perf_counter()

    try:
        if args.mode == "recognize":
            text = recognize_batch(client=client, recognizer=recognizer, audio_path=audio_path)
        else:
            wav = read_wav_pcm16_mono_16khz(audio_path)
            chunks = iter_pcm16_chunks(pcm16le=wav.pcm16le, sample_rate_hz=wav.sample_rate_hz, chunk_ms=args.chunk_ms)
            text = recognize_streaming_replay(
                client=client,
                recognizer=recognizer,
                pcm16_chunks=chunks,
                interim_results=bool(args.interim),
            )

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        raise SystemExit(1)

    dt_ms = (time.perf_counter() - t0) * 1000.0
    print(f"[google-stt] mode={args.mode} time_ms={dt_ms:.1f} model={stt_model()} location={location}", file=sys.stderr)

    # Plain transcript only on stdout.
    sys.stdout.write((text or "").strip() + "\n")


if __name__ == "__main__":
    main()
