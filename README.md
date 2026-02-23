# my-speech-google

A focused playground to build a **speech loop** using **Google APIs**:

`STT (speech-to-text) → DSPy (LLM transform) → TTS (text-to-speech)`

North-star: a usable loop similar in spirit to `voxmlx/stt_playground`, but implemented in this repo.

## Quickstart

Prereqs:
- `uv`
- Audio I/O (PortAudio) working for `sounddevice`

Install deps:

```bash
uv sync
```

## Scripts

### 1) TTS: speak text

```bash
uv run msg-tts -t "Hello from Google TTS"
```

### 2) STT file: transcribe a wav

```bash
uv run msg-stt-file path/to/audio.wav
```

### 3) STT mic: streaming transcription with partials

Uses Cloud STT v2 streaming (bidirectional gRPC under the hood).

```bash
uv run msg-stt-mic
# press ENTER to stop
```

### 4) Full loop (North-star)

```bash
uv run msg-loop
```

## Credentials

We do **not** manage `.env` here.

- Cloud STT/TTS typically require ADC (e.g. `GOOGLE_APPLICATION_CREDENTIALS` + enabled APIs).
- DSPy/Gemini uses `GEMINI_API_KEY` (or `GOOGLE_API_KEY`).
