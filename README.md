# my-speech-google

North-star (see `docs/01-goals-and-success-criteria.md`): a usable speech loop:

**Mic → streaming STT (partials) → final transcript → respond → TTS speak back**

## Primary stack (Phase 1)

The main app is **Elixir/Phoenix LiveView** (ported from `/Users/cgint/dev-external/voxmlx/stt_playground`).

- The Phoenix app orchestrates the loop + UI.
- STT/TTS are provided via **Python port workers** (Phase 1), backed by **Google APIs**.
- Later we can replace the workers with **pure Elixir** implementations (Phase 2).

## Run (Phoenix app)

Prereqs:
- Elixir
- `uv` (used to run the Python workers)
- Google Cloud credentials (ADC) + Speech-to-Text / Text-to-Speech APIs enabled

```bash
mix deps.get
mix setup
mix phx.server
```

Open: http://localhost:4000

### Required env vars

- `GOOGLE_CLOUD_PROJECT` (or `VERTEXAI_PROJECT`)

### Optional STT env vars

- `STT_LOCATION` (default: `eu`)
- `STT_LANGUAGE_CODES` (default: `en-US`)
- `STT_MODEL` (default: `chirp_3`)
- `STT_RECOGNIZER_ID` (default: `_`)

### Optional TTS env vars

- `TTS_VOICE_NAME` (default: `en-US-Neural2-F`)
- `TTS_LANGUAGE_CODE` (default: `en-US`)
- `TTS_SAMPLE_RATE_HZ` (default: `24000`)

## Python prototypes (still in repo)

There is also a standalone Python prototype under `src/my_speech_google/` (historical / for experience gathering).
The Phoenix app is the primary north-star path.
