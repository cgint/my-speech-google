# RFC: PubSub-based Event Bus for STT/TTS session events

## Status / Decision (TL;DR)
Adopt a **Phoenix.PubSub-backed Event Bus** as the primary transport for STT/TTS session events.

- Providers broadcast to per-session topics (e.g. `"stt:<session_id>"`, `"tts:<session_id>"`).
- LiveView subscribes to a session topic (only when `connected?(socket)`), and updates UI state from `handle_info/2`.
- Introduce a small wrapper module (`SttPlayground.EventBus`) to centralize topic naming + broadcast/subscribe.

This reduces coupling to `owner_pid`, enables multiple consumers per session, and clarifies the system architecture.

## Diagram
![PubSub event bus](./diagrams/pubsub_event_bus.svg)

---

## Evidence / Motivation
Current event routing is **process-to-process** (providers store an `owner_pid` and `send/2` messages directly). That works, but:

- It couples providers to LiveView process identity and lifecycle.
- Adding a second consumer (e.g. recorder / metrics / logger) requires new wiring.
- Testing and observability become more “who holds which pid?” than “what events are emitted?”

Elixir/Phoenix provides PubSub out of the box, and this repo already starts it:

- `SttPlayground.Application` includes `{Phoenix.PubSub, name: SttPlayground.PubSub}`.

## Goals
- Make STT/TTS events **multi-consumer** by default (UI, logger, recorder, etc.).
- Reduce provider coupling to LiveView (`owner_pid` becomes optional / transitional).
- Centralize and standardize event delivery patterns (topic naming, message formats).
- Make it easy to test event streams by subscribing in tests.

## Non-goals
- Durable queues or guaranteed delivery (Phoenix PubSub is in-memory broadcast).
- Major schema redesign of STT/TTS payloads (keep `%{"event" => ...}` maps).
- Full session lifecycle re-architecture in the first step.

---

## Proposed Design

### Topic naming (best practice)
Use a consistent `"resource:<id>"` pattern:

- STT: `"stt:#{session_id}"`
- TTS: `"tts:#{session_id}"`

(Optionally, we can add a global topic later like `"stt:sessions"` for coarse events.)

### Message shape
Broadcast plain Elixir tuples so LiveView can handle them with `handle_info/2`.

- STT: `{:stt_event, payload}`
- TTS: `{:tts_event, payload}`

Where `payload` remains the current map format, e.g.

- partial: `%{"event" => "partial", "session_id" => ..., "final_text" => ..., "interim_text" => ...}`
- final: `%{"event" => "final", "session_id" => ..., "text" => ...}`
- error: `%{"event" => "error", "session_id" => ..., "message" => ...}`

### Wrapper module: `SttPlayground.EventBus`
Create a small module that wraps PubSub usage:

- `stt_topic(session_id)` / `tts_topic(session_id)`
- `subscribe_stt(session_id)` / `subscribe_tts(session_id)`
- `broadcast_stt(session_id, payload)` / `broadcast_tts(session_id, payload)`

Benefits:
- Central place for topic naming.
- Easy to mock/replace in tests if needed.
- Prevents PubSub calls from being scattered across providers/UI.

### LiveView subscription best practice
Subscribe only when the LV is connected:

```elixir
if connected?(socket) do
  SttPlayground.EventBus.subscribe_stt(session_id)
end
```

Notes:
- LiveView processes automatically drop subscriptions when they terminate.
- Explicit unsubscribe is usually unnecessary unless we dynamically change topics.

---

## Migration / Implementation Plan (safe + incremental)

### Step 0 — Prep
- Add `SttPlayground.EventBus`.
- Add a minimal “pubsub enabled” config flag if we want to stage rollout (optional).

### Step 1 — Dual-delivery (temporary)
- STT/TTS providers broadcast to PubSub **and** still `send(owner_pid, ...)`.
- Consumers should only process one path to avoid double handling.
  - Easiest: migrate LiveView to PubSub and then remove direct-send handling.

### Step 2 — Migrate LiveView
- On start session: subscribe to `stt:<session_id>`.
- Handle `{:stt_event, payload}` in `handle_info/2`.
- Keep current UI logic (final vs interim) unchanged; only transport changes.

### Step 3 — Remove `owner_pid` from providers (after stabilization)
- Stop passing `owner_pid` through provider/session state.
- Remove owner monitoring logic where it exists solely for message routing.

### Step 4 — Optional: introduce a session manager
If we want to fully decouple UI from STT session lifecycle:
- Add a `SttPlayground.STT.SessionManager` that owns session processes and provides explicit APIs.
- UI becomes just a controller + subscriber.

---

## Testing Strategy

### Provider tests
- In ExUnit, `Phoenix.PubSub.subscribe(SttPlayground.PubSub, topic)` in the test process.
- Trigger provider action.
- `assert_receive {:stt_event, payload}`.

This avoids needing LiveView tests for basic event correctness.

### LiveView tests (optional)
If we later want confidence on the UI wiring:
- Use `Phoenix.LiveViewTest` to mount the LV.
- Broadcast on the topic.
- Assert rendered output changes.

---

## Risks / Tradeoffs
- PubSub is best-effort broadcast (not durable). For our UI/UX loop, that’s fine.
- During “dual delivery” we must avoid double-processing (temporary migration hazard).
- PubSub makes it easier to add consumers; we still need to keep payloads stable and versioned if they evolve.
