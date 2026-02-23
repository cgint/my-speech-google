# MVP proposals (what to build first)

## Diagram

![STT → LLM → TTS loop](./diagrams/speech_loop.svg)

## MVP 0 — Sanity checks (fast)

Goal: confirm we can authenticate and call *something* successfully.

- Cloud TTS: synthesize a short sentence to a WAV file (based on `standard_tts.py`).
- Cloud STT: transcribe a known WAV file (based on `chirp_speech_recognition.py`).

Output: 2 CLI commands that work reliably on your machine.

## MVP 1 — Deterministic baseline (Cloud STT v2 + Cloud TTS)

**Shape**
- Input: `.wav` file (or mic recorded to `.wav`)
- STT: Google Cloud Speech-to-Text v2 recognize
- Response: for now, just echo transcript or apply a trivial transform
- TTS: Google Cloud Text-to-Speech synthesize to `.wav`

**Why this first**
- Keeps the pipeline honest: STT is “verbatim transcription” oriented.
- Single credential story (GCP).

**Risks**
- Recognizer/model/region complexity (as seen in the Chirp experiment).

## MVP 2 — Interactive baseline (Gemini Live session)

**Shape**
- Use Gemini Live session to get low-latency interaction.
- Potentially: audio-in → text-out and/or audio-out.

**Why**
- If the real goal is an “interaction loop”, this may be the shortest path to a delightful demo.

**Risks**
- Harder to guarantee pure transcription.
- Different auth story (API key).

## MVP 3 — Streaming STT (partials)

**Shape**
- Mic capture → chunked PCM stream
- STT streaming API (if we choose Cloud STT v2 streaming) OR pseudo-streaming:
  - buffer chunks and periodically run recognize for partials

**Why**
- This is what makes the system feel “alive”.

**Risks**
- More moving parts (audio formats, buffering, backpressure, partial merging).

---

## Decision prompt (to unblock next steps)

Pick one axis to optimize first:

1) **Accuracy/verbatim** transcription → prefer MVP 1.
2) **Real-time feel** and conversational UX → prefer MVP 2/3.

Once you pick, we can write a concrete plan (files, scripts, verification commands) and then you can say “Go” to implement.
