# Other repos: intent + flow map (and how it informs *this* repo)

We want to keep **focus on this repo** (`my-speech-google`), but we can borrow proven patterns from nearby projects.

## 1) `speaks.sh` + `speak-to-me` (Gemini Live audio out)

Evidence:
- `~/.local/bin/speaks.sh` runs `uv run speak ...` inside `/Users/christian.gintenreiter/dev/speak-to-me`.
- `speak-to-me/pyproject.toml` defines:
  - `speak = experiments.gemini_live_audio:main`

Implication:
- Your current “TTS” path is actually **Gemini Live audio generation** (not Cloud TTS), with:
  - streaming audio chunks back
  - optional realtime playback

How it helps this repo:
- If we pick **Gemini Live** for STT/transcription as well, we can potentially implement a *single-session* loop.

## 2) `speak-to-me/experiments/chirp_speech_recognition.py` (Cloud STT v2 / Chirp)

Evidence:
- Uses `google.cloud.speech_v2` + regional endpoint via `ClientOptions(api_endpoint=f"{location}-speech.googleapis.com")`.
- Creates/lists a **Recognizer** and then calls `recognize`.

Implication:
- Cloud STT v2 is very feasible, but has **region + recognizer** complexity.
- In early steps, we might reduce complexity by using the implicit recognizer `recognizers/_` (see `docs/07e-validated-google-cloud-stt-links.md`).

## 3) `dev-external/voxmlx` STT playground (STT → DSPy/LLM → TTS)

Evidence:
- `PORT_BASED_PYTHON_STT_PLAYGROUND.md` describes a loop:
  - browser captures PCM chunks → LiveView → Port → Python worker → partial+final transcripts

Implication:
- Even if we don’t use Elixir here, the *shape* of a streaming speech system is clear:
  - buffer chunks
  - emit partials periodically
  - finalize on stop

How it helps this repo:
- It provides a reference “rough flow” for streaming interaction.

## 4) `elix-live-chat` Voxtral realtime WS (stream in → text deltas)

Evidence:
- `lib/live_ai_chat/mistral/realtime_transcription_ws.ex` implements a realtime WS client with:
  - `input_audio.append` / `input_audio.end`
  - `transcription.text.delta` / `transcription.done`

How it helps this repo:
- It’s a proven event model for partial transcripts. We can mirror this in our own abstraction even if the underlying provider is Google.

---

## What this means for *my-speech-google*

We have two coherent directions:

1) **Cloud STT v2 + Cloud TTS**
- Deterministic STT pipeline; GCP credentials; likely better “verbatim transcription”.

2) **Gemini Live (audio in/out + transcription)**
- “Interaction loop first”; potentially simplest path to a delightful demo.

Next step is to decide which direction matches the real intent of the experiment.
