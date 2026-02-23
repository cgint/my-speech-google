#!/usr/bin/env python3
"""STT port worker for Phoenix/Elixir, backed by Google Cloud Speech-to-Text v2.

Protocol (JSON over stdio, packet: 4 bytes big-endian length):

Commands from Elixir:
- {cmd: "start_session", session_id}
- {cmd: "audio_chunk", session_id, pcm_b64}
    - pcm_b64 is base64 of raw Float32 PCM bytes (f32le) at 16kHz mono
- {cmd: "stop_session", session_id}
- {cmd: "shutdown", session_id: "_"}

Events to Elixir:
- {event: "ready"}
- {event: "session_started", session_id}
- {event: "partial", session_id, text, chunk_count}
- {event: "final", session_id, text}
- {event: "error", session_id, message}

Notes:
- We intentionally emit **final** only after receiving stop_session,
  because the Elixir side treats "final" as terminal for the session.
"""

from __future__ import annotations

import base64
import json
import os
import queue
import struct
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Iterator

import numpy as np
from google.api_core.client_options import ClientOptions
from google.cloud import speech_v2


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


def _env(name: str, default: str | None = None) -> str | None:
    v = os.environ.get(name)
    return v if v is not None and v != "" else default


def _project_id() -> str:
    pid = _env("GOOGLE_CLOUD_PROJECT") or _env("VERTEXAI_PROJECT")
    if not pid:
        raise RuntimeError("Missing GOOGLE_CLOUD_PROJECT (or VERTEXAI_PROJECT)")
    return pid


def _location() -> str:
    return str(_env("STT_LOCATION", "eu"))


def _recognizer_id() -> str:
    # implicit recognizer by default
    return str(_env("STT_RECOGNIZER_ID", "_"))


def _model() -> str:
    return str(_env("STT_MODEL", "chirp_3"))


def _language_codes() -> list[str]:
    langs = str(_env("STT_LANGUAGE_CODES", "en-US"))
    return [s.strip() for s in langs.split(",") if s.strip()]


def _client(location: str) -> speech_v2.SpeechClient:
    return speech_v2.SpeechClient(
        client_options=ClientOptions(api_endpoint=f"{location}-speech.googleapis.com")
    )


def _recognizer_resource(project_id: str, location: str, recognizer_id: str) -> str:
    parent = f"projects/{project_id}/locations/{location}"
    return f"{parent}/recognizers/{recognizer_id}"


def f32le_16k_mono_to_s16le(pcm_f32le: bytes) -> bytes:
    if not pcm_f32le:
        return b""

    # Interpret as little-endian float32.
    f32 = np.frombuffer(pcm_f32le, dtype="<f4")
    # clip to [-1, 1] then scale to int16.
    f32 = np.clip(f32, -1.0, 1.0)
    i16 = (f32 * 32767.0).astype("<i2")
    return i16.tobytes(order="C")


@dataclass
class Session:
    session_id: str
    q: "queue.Queue[bytes | None]" = field(default_factory=queue.Queue)
    stop_requested: threading.Event = field(default_factory=threading.Event)
    chunk_count: int = 0


def streaming_thread(session: Session) -> None:
    try:
        project_id = _project_id()
        location = _location()
        client = _client(location)
        recognizer = _recognizer_resource(project_id, location, _recognizer_id())

        explicit = speech_v2.ExplicitDecodingConfig(
            encoding=speech_v2.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16_000,
            audio_channel_count=1,
        )

        recognition_config = speech_v2.RecognitionConfig(
            explicit_decoding_config=explicit,
            language_codes=_language_codes(),
            model=_model(),
        )

        streaming_config = speech_v2.StreamingRecognitionConfig(
            config=recognition_config,
            streaming_features=speech_v2.StreamingRecognitionFeatures(
                interim_results=True,
            ),
        )

        final_segments: list[str] = []
        last_interim: str = ""

        def reqs() -> Iterator[speech_v2.StreamingRecognizeRequest]:
            yield speech_v2.StreamingRecognizeRequest(
                recognizer=recognizer,
                streaming_config=streaming_config,
            )
            while True:
                chunk = session.q.get()
                if chunk is None:
                    return
                if not chunk:
                    continue
                yield speech_v2.StreamingRecognizeRequest(audio=chunk)

        # Consume responses until stream ends.
        for resp in client.streaming_recognize(requests=reqs()):
            for result in resp.results:
                if not result.alternatives:
                    continue
                text = (result.alternatives[0].transcript or "").strip()
                if not text:
                    continue

                if result.is_final:
                    final_segments.append(text)
                    last_interim = ""
                else:
                    last_interim = text

                # During recording we only emit partials.
                combined = " ".join([t for t in (final_segments + ([last_interim] if last_interim else [])) if t])
                if combined:
                    send_packet_or_exit(
                        {
                            "event": "partial",
                            "session_id": session.session_id,
                            "text": combined,
                            "chunk_count": session.chunk_count,
                        }
                    )

        # If the stream ended naturally (rare), emit final if stop was requested.
        if session.stop_requested.is_set():
            final_text = " ".join([t for t in final_segments if t]).strip() or last_interim.strip()
            send_packet_or_exit({"event": "final", "session_id": session.session_id, "text": final_text})

    except SystemExit:
        return
    except Exception as e:
        send_packet({"event": "error", "session_id": session.session_id, "message": str(e)})


def main() -> None:
    sessions: dict[str, Session] = {}
    sessions_lock = threading.Lock()

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
            session = Session(session_id=session_id)
            t = threading.Thread(target=streaming_thread, args=(session,), daemon=True)

            with sessions_lock:
                sessions[session_id] = session

            t.start()
            send_packet_or_exit({"event": "session_started", "session_id": session_id})
            continue

        if cmd == "audio_chunk":
            with sessions_lock:
                session = sessions.get(session_id)
            if session is None:
                send_packet_or_exit(
                    {"event": "error", "session_id": session_id, "message": "unknown session"}
                )
                continue

            pcm_b64 = msg.get("pcm_b64", "")
            try:
                pcm_f32le = base64.b64decode(pcm_b64)
            except Exception:
                send_packet_or_exit({"event": "error", "session_id": session_id, "message": "invalid base64"})
                continue

            try:
                pcm_s16le = f32le_16k_mono_to_s16le(pcm_f32le)
            except Exception as e:
                send_packet_or_exit(
                    {"event": "error", "session_id": session_id, "message": f"pcm convert failed: {e}"}
                )
                continue

            session.chunk_count += 1
            session.q.put(pcm_s16le)
            continue

        if cmd == "stop_session":
            with sessions_lock:
                session = sessions.pop(session_id, None)

            if session is None:
                send_packet_or_exit(
                    {"event": "error", "session_id": session_id, "message": "unknown session"}
                )
                continue

            # Signal the streaming thread to end the request generator.
            session.stop_requested.set()
            session.q.put(None)

            # Emit final transcript after the stream has ended. We don't join here;
            # the streaming thread will emit final once it sees the stream end.
            # However, some errors can cause it to not reach the end-of-stream path.
            # In that case Elixir will get an "error" event.
            continue

        send_packet_or_exit({"event": "error", "session_id": session_id, "message": f"unknown cmd: {cmd}"})


if __name__ == "__main__":
    main()
