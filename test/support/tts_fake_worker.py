#!/usr/bin/env python3
import base64
import json
import os
import struct
import sys


def recv_packet():
    header = sys.stdin.buffer.read(4)
    if not header or len(header) < 4:
        return None
    length = struct.unpack(">I", header)[0]
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        return None
    return payload


def send_packet(message):
    data = json.dumps(message).encode("utf-8")
    try:
        sys.stdout.buffer.write(struct.pack(">I", len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        return True
    except (BrokenPipeError, OSError):
        return False


def main():
    sessions = {}
    if not send_packet({"event": "ready"}):
        return

    # 256 samples of silence (float32 little-endian)
    silent_f32le = struct.pack("<" + "f" * 256, *([0.0] * 256))
    silent_b64 = base64.b64encode(silent_f32le).decode("ascii")

    while True:
        payload = recv_packet()
        if payload is None:
            break

        msg = json.loads(payload.decode("utf-8"))
        cmd = msg.get("cmd")
        sid = msg.get("session_id")

        if cmd == "shutdown":
            send_packet({"event": "bye"})
            break
        elif cmd == "start_session":
            sessions[sid] = True
            send_packet({"event": "session_started", "session_id": sid})
        elif cmd == "stop_session":
            sessions.pop(sid, None)
            send_packet({"event": "session_stopped", "session_id": sid})
        elif cmd == "speak_text":
            if sid not in sessions:
                send_packet({"event": "error", "session_id": sid, "message": "unknown session"})
                continue

            # emit one chunk + done
            send_packet(
                {
                    "event": "audio_chunk",
                    "session_id": sid,
                    "seq": 0,
                    "pcm_b64": silent_b64,
                    "sample_rate": 24000,
                    "channels": 1,
                    "format": "f32le",
                }
            )
            send_packet({"event": "session_done", "session_id": sid})


if __name__ == "__main__":
    try:
        main()
    finally:
        os._exit(0)
