# 14 — Elixir-native STT/TTS providers with switchable backend (PythonPort ↔ Elixir)

## Summary / outcome
We will introduce a **stable Elixir provider contract** for STT and TTS and implement two interchangeable backends:

- **`python_external`** (current approach): Elixir GenServers + Python Port workers.
- **`elixir_google`** (target): Elixir-only integrations using:
  - **Google TTS via HTTP** (Finch + Goth)
  - **Google STT v2 streaming via gRPC** (prefer `ex_google_stt` + Goth), including interim/partials.

Switching providers will be a **config-only change**. LiveView/UI and the rest of the app will depend only on the **facade modules** (`SttPlayground.STT` / `SttPlayground.TTS`).

## Diagram
![Provider switching plan](./diagrams/provider_switching_plan.svg)

## Why this plan
- Keeps the repo aligned with the **Elixir-first** constraint while preserving the ability to fall back to the known-good Python streaming implementation.
- Minimizes churn: we can keep **~80%+** of the existing `stt_playground` structure and only swap the backend.
- Enables incremental delivery: **TTS first** (simpler), then **STT streaming** (harder).

## Non-goals (for this phase)
- No UI/contract redesign.
- No “perfect” long-term abstraction over all possible STT/TTS vendors.
- No automatic creation/management of STT v2 Recognizers inside the app (we can do that later).

---

## Target contract (stable interface)
### Message contract (unchanged)
The session owner (typically a LiveView or session process) continues to receive:

- STT: `{:stt_event, map}` where `map["event"]` is one of:
  - `"ready" | "session_started" | "partial" | "final" | "error" | "overload"`
- TTS: `{:tts_event, map}` where `map["event"]` is one of:
  - `"ready" | "session_started" | "audio_chunk" | "session_done" | "error"`

### Elixir facade API (what the rest of the app calls)
Create stable facade modules:

- `SttPlayground.STT`:
  - `start_session(session_id, owner_pid, opts \\ [])`
  - `audio_chunk(session_id, pcm_b64)`
  - `stop_session(session_id)`

- `SttPlayground.TTS`:
  - `start_session(session_id, owner_pid, opts \\ [])`
  - `speak_text(session_id, text)`
  - `stop_session(session_id)`

These facades delegate to the configured provider.

---

## Provider modules
### Behaviours
- `SttPlayground.STT.Provider`
- `SttPlayground.TTS.Provider`

Each provider implements the same callbacks as the facade.

### Implementations
**Keep (existing):**
- `SttPlayground.STT.Providers.PythonPort` (wraps current `SttPlayground.STT.PythonPort` GenServer)
- `SttPlayground.TTS.Providers.PythonPort` (wraps current `SttPlayground.TTS.PythonPort` GenServer)

**Add (new Elixir-only):**
- `SttPlayground.TTS.Providers.GoogleHttp`
  - Uses `Goth` to fetch OAuth token
  - Uses `Finch` to call `texttospeech.googleapis.com/v1/text:synthesize`
  - Base64-decodes `audioContent`
  - Converts to float32 PCM (`f32le`) and emits `audio_chunk` events (same schema)

- `SttPlayground.STT.Providers.GoogleGrpc`
  - Preferred approach: use `ex_google_stt` (built on `grpc`) to manage the STT v2 streaming session
  - Uses `Goth` for authentication
  - Supports interim results / partials (`streaming_features.interim_results=true` in STT v2 terms)
  - Handles **regional endpoint** selection based on configured location
  - Requires a configured **Recognizer resource name**

---

## Configuration / switching
Add config keys:

- `config :stt_playground, :stt_provider, SttPlayground.STT.Providers.PythonPort`
- `config :stt_playground, :tts_provider, SttPlayground.TTS.Providers.PythonPort`

Later switch to:

- `...GoogleGrpc`
- `...GoogleHttp`

No other code should need to change to toggle the backend.

---

## Audio formats & conversion
### STT input (browser → STT)
Current browser capture sends:
- base64 of raw **float32 little-endian** PCM bytes (`f32le`) at **16 kHz** mono.

Google STT expects linear PCM (typically `LINEAR16` / signed int16). The Elixir-native STT provider must:
- decode base64
- convert `f32le` samples to `s16le`
- stream bytes to STT

### TTS output (Google → browser)
Browser playback expects:
- base64 of **float32 little-endian** PCM bytes (`f32le`) mono (AudioContext typically 24k).

Google TTS commonly returns `LINEAR16`. The Elixir-native TTS provider must:
- decode base64 `audioContent`
- convert `s16le` → `f32le`
- chunk and emit `audio_chunk` events

---

## Execution plan (incremental)
### Step 1 — Introduce the seam (safe refactor)
1. Add behaviours + facades (`SttPlayground.STT` / `SttPlayground.TTS`).
2. Add `Providers.PythonPort` adapters.
3. Update call sites to use facades only.
4. Add provider contract tests (shared test suite) that run against the Python providers.

**Exit criteria:** app behaves identical; switching provider module is a no-op (still Python).

### Step 2 — Elixir-native TTS (GoogleHttp)
1. Start `Goth` and `Finch` under supervision (if not already).
2. Implement `TTS.Providers.GoogleHttp` with the same session semantics and emitted events.
3. Add tests for:
   - token fetch + request formation (unit)
   - chunking and event emission

**Exit criteria:** you can switch TTS provider in config and LiveView playback still works.

### Step 3 — Elixir-native STT (GoogleGrpc streaming)
1. Add dependency on `ex_google_stt` (preferred) and configure it for:
   - recognizer resource
   - location/regional endpoint
   - interim results
2. Implement `STT.Providers.GoogleGrpc`:
   - per-session process managing stream lifecycle
   - map interim transcripts to `partial`
   - on stop, emit `final` consistent with current semantics
3. Contract tests: ensure partials and final ordering matches Python provider.

**Exit criteria:** you can switch STT provider in config and get stable partials + finals.

### Step 4 — Deprecate Python (optional)
Once parity is reached and we’re confident, we can:
- keep Python provider as fallback
- or remove Python workers from default runtime (still available for troubleshooting)

---

## Telemetry / observability
Keep lightweight telemetry around:
- worker/provider start/ready/exit
- per-session start/stop
- chunk ingress/processed/dropped (STT)

This is important when comparing Python vs Elixir providers (latency/partial frequency).

---

## Open questions (not blocking the seam)
- STT recognizer management: do we assume an external `gcloud`-created recognizer, or add creation to app setup later?
- Precise STT finalization semantics: do we keep “final only after stop_session” forever, or allow immediate finals?
- Exact chunk sizing for STT streaming (time-based vs sample-count-based).
