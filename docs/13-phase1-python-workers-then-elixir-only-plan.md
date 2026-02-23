# Phase 1 (Python workers) → Phase 2 (Elixir-only) migration plan

## Status (top)

- **North-Star (from `docs/01-goals-and-success-criteria.md`)** remains: **(3) Loop** — mic → partial STT → final → respond → TTS speak back.
- **Primary stack constraint:** main app is **Elixir (Phoenix/LiveView)** and should reuse **~80%+** of `/Users/cgint/dev-external/voxmlx/stt_playground`.
- **Approach:** ship the loop quickly via **Elixir app + Python port workers** (Phase 1), then replace workers with **pure Elixir Google API clients** (Phase 2) without changing UI/loop orchestration.

## Diagram

![Migration plan](./diagrams/migration_plan.svg)

## Core design rule (to enable later Elixir-only)

Freeze a stable internal contract inside the Elixir app:

- A **provider behaviour** for STT/TTS used by LiveView/loop code.
- Provider implementations:
  - Phase 1: `Port`-based providers (Python workers)
  - Phase 2: `Elixir`-native providers (HTTP + later gRPC)

This ensures swapping implementation does **not** require touching UI/flow code.

## Phase 1 — Elixir main app + Python workers (Google-backed)

### Goal

Deliver the North-Star loop (#3) with streaming partials, while maximizing reuse of `stt_playground`.

### What we reuse (80%+)

From `/Users/cgint/dev-external/voxmlx/stt_playground`:
- Phoenix/LiveView UI
- Browser mic streaming hook (AudioWorklet) + chunk forwarding
- Browser TTS streaming playback (`AudioContext` + float32 chunks)
- Elixir orchestration: supervision tree, session lifecycle, telemetry, backpressure/queueing patterns
- Port protocol & message routing patterns

### What changes in Phase 1

Only the integrated STT/TTS engines:

1) **STT worker**: swap Voxtral transcription for **Google Cloud Speech-to-Text v2**.
   - Keep protocol: `start_session`, `audio_chunk`, `stop_session`.
   - Emit events: `partial`, `final`, `error`.
   - Audio format handling:
     - input from browser: **f32le 16kHz mono** (base64)
     - convert to **s16le (LINEAR16) 16kHz mono** for Cloud STT v2 streaming

2) **TTS worker**: swap KittenTTS for a **Google TTS backend**.
   - Keep protocol: `start_session`, `speak_text`, `stop_session`.
   - Emit events: `audio_chunk`, `session_done`, `error`.
   - Output format:
     - send **f32le** chunks (base64) so the existing browser player stays unchanged
     - convert from Cloud TTS PCM16 → float32 (or use a backend that already yields float32)

### Phase 1 concrete implementation steps (files)

1) **Import/replicate the Elixir app skeleton**
   - Bring in `mix.exs`, `config/*`, `lib/*`, `assets/*`, `priv/*`, `test/*` following `stt_playground`.
   - Rename namespaces to this repo’s app name.

2) **Place Python workers inside this repo**
   - `./python/stt_port_worker.py` (Google Cloud STT v2 streaming)
   - `./python/tts_port_worker.py` (Google TTS backend)
   - Keep `uv`-based launch (like `stt_playground`) for dependency isolation.

3) **Wire Elixir ports to these workers**
   - Keep Elixir modules structurally identical to `SttPlayground.STT.PythonPort` and `SttPlayground.TTS.PythonPort`.
   - Only adjust default worker paths.

4) **Run the loop end-to-end**
   - Browser mic → STT partials/final → responder → TTS playback.

5) **Write down runbook + smoke verification**
   - Minimal env vars and prerequisites (ADC, project id).
   - “Known good” commands for local verification.

### Phase 1 verification checklist

- `mix setup`
- `mix phx.server`
- In browser:
  - start recording → see **partial** events
  - stop → see **final** transcript
  - trigger speak-back → hear audio, receive `session_done`

## Phase 2 — Remove Python; go Elixir-only

### Phase 2A — Elixir-only (REST) first

- Implement **Cloud TTS REST** in Elixir (Req + Goth)
- Implement **Cloud STT file recognize (REST)** in Elixir (Req + Goth)
- Keep Phase 1 streaming STT via Python until gRPC streaming is validated

### Phase 2B — Elixir-only streaming STT (gRPC)

- Implement Cloud STT v2 **bidirectional streaming gRPC** in Elixir.
- Ensure we can emit identical `partial/final` events as Phase 1.
- Flip provider selection to Elixir implementation.
- Delete Python STT worker.

### Phase 2C — Elixir-only TTS streaming (if required)

- Cloud TTS is typically request/response; we can still stream playback by chunking audio buffers to the browser.
- Swap out Python TTS worker once Elixir implementation is stable.

## Decisions / toggles to keep explicit

- STT backend choice: Cloud STT v2 (first), later evaluate Gemini Live transcription only if needed.
- TTS backend choice for Phase 1: Cloud TTS vs Gemini Live audio out.
- Provider selection mechanism in Elixir (`config/runtime.exs`): `:python_port` vs `:native_http` vs `:native_grpc`.
