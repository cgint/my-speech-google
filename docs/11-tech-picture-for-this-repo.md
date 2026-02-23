# Tech picture for this repo (Google speech)

## Diagram

![Provider decision](./diagrams/provider_decision.svg)

## What we have (evidence-based)

### Working TTS path today (your environment)

- `speaks.sh` is a thin wrapper that runs `uv run speak ...` inside `dev/speak-to-me`.
- `dev/speak-to-me` implements `speak` via **Gemini Live audio output** (`experiments/gemini_live_audio.py`).

Implication:
- Your “default TTS” today is already in the **Gemini family** (API-key based), not necessarily Cloud Text-to-Speech.

### Existing STT attempt

- `dev/speak-to-me/experiments/chirp_speech_recognition.py` uses **Google Cloud Speech-to-Text v2** (`google.cloud.speech_v2`) to do file-based recognition.

Observed complexity:
- regional endpoints + Recognizer resources + model identifiers.

### Additional confirmed capability: Gemini Live audio-in + transcription

- The locally installed `google-genai` SDK (as used by `speak-to-me`) supports:
  - sending audio via `session.send_realtime_input(media=types.Blob(... mime_type='audio/pcm;rate=16000'))`
  - enabling transcription via `LiveConnectConfig.input_audio_transcription=AudioTranscriptionConfig()`
  - receiving transcription events under `LiveServerContent.input_transcription`

(See `docs/08b-gemini-live-api-transcription-validated.md`.)

## The two main technical directions

### Direction 1: Google Cloud STT v2 + Cloud TTS

Best when:
- We want **verbatim** transcription and a clean STT contract.

Key characteristics:
- gRPC client library
- ADC/service-account auth
- Recognizer management (but we can start with `recognizers/_`)

### Direction 2: Gemini Live API (audio in/out)

Best when:
- We want the **interactive loop** quickly (low-latency voice UX).

Key characteristics:
- WebSocket-based session
- API key auth
- model can do more than STT (it’s a multimodal model session)

## What I recommend we decide next (to proceed efficiently)

Pick the repo’s **first milestone**:

1) **STT baseline milestone**: “Given a WAV/mic recording, produce transcript.”
   - Then decide Cloud STT vs Gemini Live transcription.

2) **Conversation loop milestone**: “Speak → get transcript → respond → speak back.”
   - Likely quickest by staying inside Gemini Live for both directions.

Once you pick one, we can write an implementation plan for this repo (scripts, dependencies, how to run, verification).
