# Reference implementations and prior art

This is a curated set of nearby code that we can reuse for patterns (streaming, chunking, supervision) without copying blindly.

## 1) voxmlx — Port-based Python STT playground

**Evidence:** `dev-external/voxmlx/PORT_BASED_PYTHON_STT_PLAYGROUND.md`

Key ideas worth reusing:
- Browser captures **PCM audio chunks** → LiveView.
- Elixir isolates Python interop behind a **single GenServer** that owns one Port.
- Uses `{:packet, 4}` framed JSON (robust vs newline framing).
- Python worker emits events:
  - `partial`, `final`, `error`, etc.

Why this matters here:
- Even if we do everything in Python in this repo, the *session protocol* and *chunk buffering → partial loop → final transcribe* structure is a proven shape.

## 2) elix-live-chat — Mistral Voxtral realtime transcription over WebSocket

**Evidence:** `dev/elix-live-chat/lib/live_ai_chat/mistral/realtime_transcription_ws.ex`

Notable patterns:
- WebSocket session starts, then `session.update` sets `audio_format`.
- Streaming input:
  - `input_audio.append` with base64 audio bytes
  - `input_audio.end` when done
- Streaming output events:
  - `transcription.text.delta`
  - `transcription.done`

Why this matters here:
- This provides a concrete “stream audio chunks → receive deltas” event model.
- If Google STT streaming has a similar incremental output, we can map the same UI/protocol structure.

## 3) speak-to-me — Google STT/TTS experiments

**Evidence:**
- `dev/speak-to-me/experiments/chirp_speech_recognition.py` (Cloud STT v2 / Chirp)
- `dev/speak-to-me/experiments/standard_tts.py` (Cloud TTS)
- `dev/speak-to-me/experiments/gemini_live_audio.py` + others (Gemini audio)

Why this matters here:
- We already have locally-tested snippets for auth + basic calls.
- We can extract a minimal, clean version into this repo once we decide the exact STT/TTS combo.
