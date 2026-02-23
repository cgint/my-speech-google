# Setup and credentials (notes)

This doc captures the credential/config surface implied by the existing experiments.

## If we use Google Cloud APIs (Speech-to-Text v2 / Text-to-Speech)

### Authentication

Evidence from `standard_tts.py` + `chirp_speech_recognition.py`:

- Uses Google Cloud client libraries (`google.cloud.*`) → typically relies on **Application Default Credentials (ADC)**.
- Common env vars you may use:
  - `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`
  - `GOOGLE_CLOUD_PROJECT=...` (or `VERTEXAI_PROJECT` is checked in the Chirp script)

> Note: per repo safety rules, we won’t edit `.env` files; we’ll document required env vars and you set them.

### APIs to enable (project-side)

- **Speech-to-Text API**
- **Text-to-Speech API**

Minimal enablement steps (console):
1. Google Cloud Console → **APIs & Services** → **Library**
2. Search and enable:
   - “Speech-to-Text API”
   - “Text-to-Speech API”

(We keep this high-level; exact org policies / billing / quota handling varies by project.)

### Region / endpoint

Evidence from Chirp experiment:
- STT v2 may require using a **regional endpoint** like:
  - `{location}-speech.googleapis.com` (example location used: `europe-west1`)

Critical: region choice impacts availability and permissions.

## If we use Gemini API (google-genai)

Evidence from `gemini_live_audio.py`:

- Uses `GEMINI_API_KEY` for auth.
- Some calls set `http_options={"api_version": "v1alpha"}`.
- Model IDs are explicit strings (preview IDs).

Risks:
- Preview model names can change; we should encapsulate them in one place in this repo when implementing.

## Audio format conventions to settle early

Recommended baseline for STT streaming:
- **16,000 Hz** sample rate
- **mono**
- **PCM16 / LINEAR16** (signed 16-bit little endian)

Notes:
- Cloud STT streaming is gRPC-based; you stream **raw PCM chunks** (not a WAV container) when doing live mic capture.
- File-based recognize is simpler because you can send the full file content (often with auto-decoding).
- Some TTS backends (e.g. Gemini Live) may emit **24kHz** PCM; either resample or play at native rate.

Reason: STT/TTS endpoints require strict format matching; most "it doesn’t work" issues are audio-format mismatches.

## Local audio capture libraries (Python)

You need one working mic capture option:
- `sounddevice` (PortAudio-based; what we use in this repo’s prototype)
- or `pyaudio` (also PortAudio-based; common in examples)

If mic capture fails, fix system PortAudio/audio permissions first before debugging STT.
