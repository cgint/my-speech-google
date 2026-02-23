# Implementation plan (self-managed)

Goal: build a **fully usable speech loop prototype** in this repo that mirrors the *flow* of `voxmlx/stt_playground`, but replaces STT+TTS with **Google APIs** while keeping a **DSPy** transformation step.

## Diagram

![Implementation flow](./diagrams/implementation_flow.svg)

## Plan (incremental, north-star aligned)

### Milestone A — TTS-only prototype ("wav-to-speech" equivalent)
- Provide a CLI to synthesize speech from text and play it.
- Implement at least one backend:
  - Google Cloud Text-to-Speech **or** Gemini Live audio-out.

### Milestone B — STT file prototype
- Provide a CLI to transcribe a WAV file to text using Google Cloud Speech-to-Text v2.
- Prefer **implicit recognizer** (`recognizers/_`) for early simplicity.

### Milestone C — Streaming STT (partials) from microphone
- Mic capture (16kHz mono PCM s16le)
- Stream audio chunks to Cloud STT v2 `streaming_recognize` (bidirectional **gRPC** stream)
- Print partial transcripts continuously + final transcript on stop
- Implementation pattern:
  - first request carries `StreamingRecognitionConfig` (incl. `interim_results=true`)
  - subsequent requests carry raw PCM chunks

### Milestone D — DSPy integration
- Add a DSPy responder that takes transcript text and produces a response.
- Use Gemini as the LM if available via environment variables.
- Keep a clean interface so we can swap prompts/programs later.

### Milestone E — Full loop (North-Star)
- `record → partials → final transcript → DSPy response → TTS speak back`
- Provide a single command to run this loop.

## Verification approach

- Commands should run locally with clear, actionable error messages when credentials are missing.
- Provide `--help` and small "smoke" scripts for each milestone.

## Notes / constraints

- No `.env` editing; rely on env vars (ADC for Cloud APIs, `GEMINI_API_KEY` for Gemini).
- Keep the code focused on this repo (external repos are reference only).
