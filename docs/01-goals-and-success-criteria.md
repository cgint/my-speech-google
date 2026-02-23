# Goals and success criteria

## What we’re trying to achieve (from `TASK_speech_google_IDEA.md`)

- Recreate the existing “little experiment” flow, but using **Google APIs** for:
  - **STT (speech-to-text)**
  - **TTS (text-to-speech)**
- TTS is already in use elsewhere (`/Users/christian.gintenreiter/dev/speak-to-me` via `speaks.sh`).
- For STT, the intended Google API is not chosen yet.

## Why this repo exists (interpretation)

- Provide a focused playground to evaluate Google’s STT/TTS options in a way that can later be composed into a full loop:
  - `STT → (DSPy/LLM-calling) → TTS`

## Proposed success criteria (to confirm)

Pick 1–2 “must-haves” for the *first* iteration:

1) **Minimum**: can transcribe a known WAV file end-to-end reproducibly.
- Input: `.wav` file on disk
- Output: transcript string

2) **Nice**: interactive / low-latency experience.
- Partial transcripts during recording (streaming or pseudo-streaming)
- Total turn latency target (example): < 1.5–2.5s for short utterances (confirm target)

3) **Loop**: can speak back.
- After transcription, generate a response (could be a stub at first) and synthesize audio.

## Non-goals (first iteration)

- Full product UX
- Perfect diarization / punctuation / domain adaptation
- Multi-language support (unless explicitly needed)

## Key decisions we need to make early

- STT provider choice:
  - Google Cloud Speech-to-Text v2 (deterministic STT)
  - Gemini audio models / Live API (more "agentic"; can do more than STT)
  - “Google Interactions” (currently unclear what exact API/product is meant)
- Batch vs streaming: do we need partials now, or later?
