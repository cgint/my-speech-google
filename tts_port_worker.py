#!/usr/bin/env python3
"""TTS port worker for Phoenix/Elixir, backed by Google Cloud Text-to-Speech.

Protocol (JSON over stdio, packet: 4 bytes big-endian length):

Commands from Elixir:
- {cmd: "start_session", session_id}
- {cmd: "speak_text", session_id, text}
- {cmd: "stop_session", session_id}
- {cmd: "shutdown", session_id: "_"}

Events to Elixir:
- {event: "ready"}
- {event: "session_started", session_id}
- {event: "audio_chunk", session_id, seq, pcm_b64, sample_rate, channels, format}
    - audio is f32le mono, chunked
- {event: "session_done", session_id}
- {event: "error", session_id, message}

Notes:
- The browser-side player in `stt_playground` expects float32 PCM chunks.
- Cloud TTS returns LINEAR16 (int16) bytes; we convert to float32.
"""

from __future__ import annotations

import base64
import json
import os
import struct
import sys
import time
from typing import Any

import numpy as np
from google.cloud import texttospeech


def recv_packet() -> bytes | None:
    header = sys.stdin.buffer.read(4)
    if not header or len(header) < 4:
        return None
    length = struct.unpack(">I", header)[0]
    if length == 0:
        return b""
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        return None
    return payload


def send_packet(message: dict[str, Any]) -> bool:
    """Send a framed JSON packet.

    Returns False if stdout is closed (e.g. Elixir Port terminated).
    """

    data = json.dumps(message).encode("utf-8")
    try:
        sys.stdout.buffer.write(struct.pack(">I", len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        return True
    except (BrokenPipeError, OSError):
        return False


def send_packet_or_exit(message: dict[str, Any]) -> None:
    if not send_packet(message):
        raise SystemExit(0)


def _env(name: str, default: str) -> str:
    v = os.environ.get(name)
    return v if v is not None and v != "" else default


def synthesize_pcm16(*, text: str) -> tuple[bytes, int]:
    """Return (pcm16_bytes, sample_rate_hz)."""

    voice_name = _env("TTS_VOICE_NAME", "en-US-Neural2-F")
    lang = _env("TTS_LANGUAGE_CODE", "en-US")
    sample_rate = int(_env("TTS_SAMPLE_RATE_HZ", "24000"))

    client = texttospeech.TextToSpeechClient()

    response = client.synthesize_speech(
        input=texttospeech.SynthesisInput(text=text),
        voice=texttospeech.VoiceSelectionParams(language_code=lang, name=voice_name),
        audio_config=texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.LINEAR16,
            sample_rate_hertz=sample_rate,
        ),
    )

    return response.audio_content, sample_rate


def pcm16_to_f32le(pcm16: bytes) -> bytes:
    if not pcm16:
        return b""
    i16 = np.frombuffer(pcm16, dtype="<i2")
    f32 = (i16.astype("<f4") / 32768.0).astype("<f4")
    return f32.tobytes(order="C")


def chunk_f32le_bytes(f32le: bytes, *, samples_per_chunk: int = 2048) -> list[bytes]:
    if not f32le:
        return []
    # f32 = 4 bytes/sample
    bytes_per_chunk = samples_per_chunk * 4
    return [f32le[i : i + bytes_per_chunk] for i in range(0, len(f32le), bytes_per_chunk)]


def main() -> None:
    sessions: dict[str, dict[str, Any]] = {}

    send_packet_or_exit({"event": "ready", "ts_ms": int(time.time() * 1000)})

    while True:
        payload = recv_packet()
        if payload is None:
            break

        try:
            msg = json.loads(payload.decode("utf-8"))
        except Exception as e:
            send_packet_or_exit({"event": "error", "message": f"invalid json: {e}"})
            continue

        cmd = msg.get("cmd")
        session_id = str(msg.get("session_id", ""))

        if cmd == "shutdown":
            send_packet_or_exit({"event": "bye"})
            break

        if not session_id:
            send_packet_or_exit({"event": "error", "message": "missing session_id"})
            continue

        if cmd == "start_session":
            sessions[session_id] = {"created_at_ms": int(time.time() * 1000)}
            send_packet_or_exit({"event": "session_started", "session_id": session_id})
            continue

        if cmd == "stop_session":
            sessions.pop(session_id, None)
            send_packet_or_exit({"event": "session_stopped", "session_id": session_id})
            continue

        if cmd == "speak_text":
            if session_id not in sessions:
                send_packet_or_exit({"event": "error", "session_id": session_id, "message": "unknown session"})
                continue

            text = str(msg.get("text", "")).strip()
            if not text:
                send_packet_or_exit({"event": "session_done", "session_id": session_id})
                continue

            try:
                pcm16, sample_rate = synthesize_pcm16(text=text)
                f32le = pcm16_to_f32le(pcm16)

                for seq, chunk in enumerate(chunk_f32le_bytes(f32le, samples_per_chunk=2048)):
                    pcm_b64 = base64.b64encode(chunk).decode("ascii")
                    send_packet_or_exit(
                        {
                            "event": "audio_chunk",
                            "session_id": session_id,
                            "seq": seq,
                            "pcm_b64": pcm_b64,
                            "sample_rate": sample_rate,
                            "channels": 1,
                            "format": "f32le",
                        }
                    )

                send_packet_or_exit({"event": "session_done", "session_id": session_id})
            except Exception as e:
                send_packet_or_exit(
                    {"event": "error", "session_id": session_id, "message": f"tts failed: {e}"}
                )

            continue

        send_packet_or_exit({"event": "error", "session_id": session_id, "message": f"unknown cmd: {cmd}"})


if __name__ == "__main__":
    main()
