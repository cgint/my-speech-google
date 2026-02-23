# Implementation plan (self-managed)

Goal: build a **fully usable speech loop prototype** in this repo that mirrors the *flow* of `voxmlx/stt_playground`, but replaces **only** STT+TTS with **Google APIs** while keeping the rest of the app structure.

**Primary stack constraint:** the “main app” is **Elixir** (Phoenix/LiveView) and should **reuse ~80%+** of `voxmlx/stt_playground` as-is.
- Keep the LiveView UI, mic streaming hook, and Elixir orchestration.
- Keep the port-based architecture (Elixir ↔ Python workers) unless we later decide to go pure-Elixir.
- Python-only CLIs can exist as prototypes, but must not become the primary north-star path.

## Diagram

![Implementation flow](./diagrams/implementation_flow.svg)

## Plan (incremental, north-star aligned)

### Milestone A — TTS worker (Google-backed) integrated into Elixir app
- Implement/replace the **TTS Python port worker** used by the Phoenix app.
- Keep the existing port protocol so the Elixir + JS side can remain unchanged:
  - `start_session`, `speak_text`, `audio_chunk`, `session_done`, `error`
- Implement at least one backend:
  - Google Cloud Text-to-Speech (ADC) **or**
  - Gemini Live audio-out (API key)
- Output to the browser as streamed `f32le` PCM chunks (what `stt_playground` expects today).

### Milestone B — STT baseline (file) for reproducibility
- Ensure we can transcribe a known WAV file end-to-end reproducibly (success criteria #1).
- This can be implemented as either:
  - a small standalone script/tool, **or**
  - an extra command in the STT port worker (preferred if it helps integration later).
- Prefer Google Cloud Speech-to-Text v2 with **implicit recognizer** (`recognizers/_`) for early simplicity.

### Milestone C — Streaming STT (partials) from microphone (Elixir UI unchanged)
- Keep the existing browser mic capture (AudioWorklet) and Elixir chunk forwarding unchanged.
- Update only the **STT Python port worker** internals to use Google STT and emit:
  - `partial` events during recording
  - `final` event on stop
- Implementation options inside the worker:
  - True streaming: Cloud STT v2 `streaming_recognize` (bidirectional gRPC), or
  - Pseudo-streaming: periodic `recognize` on the accumulated audio buffer (acceptable early prototype).

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
