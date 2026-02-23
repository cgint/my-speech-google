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

## Success criteria (confirmed by user)

**North-Star:** We have to aim for 3. straight as the initial goal overall.

**How to reach the goal:** While heading towards the goal it will be helpful to create prototypes that e.g. only do wav-to-speech (as in speak-to-me) or speech-to-text solely on files. This should help a lot in getting the red-path done without thinking about the integrateion yet - while always having the north-star (3. Loop) in mind to be clear to work towars that and so that the initial small parts can be integrated later.

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
- Multi-language support (unless explicitly needed or automatically given by the APIs)

## Key decisions we need to make early

- STT provider choice:
  - Google Cloud Speech-to-Text v2 (deterministic STT)
  - Gemini audio models / Live API (more "agentic"; can do more than STT)
  - “Google Interactions” (currently unclear what exact API/product is meant)
- Batch vs streaming: do we need partials now, or later?
