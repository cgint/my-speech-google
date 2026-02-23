# Repository agent notes

## Status / overview (keep this short)
This file is a lightweight, long-lived companion to the work in this repo. It captures *non-flow* context that helps the assistant stay a critical-yet-constructive partner while we iterate.

- Primary idea source: `./TASK_speech_google_IDEA.md`
- Working mode: we follow the **Clarity First** protocol (Plan first → wait for explicit “Go/Approved” before implementation changes).

## Assistant working memory (side notes; not main flow)

Purpose: keep *non-flow* context that helps me help you (intent gathering, assumptions, risks, learnings, pointers). This is **not** the main workflow/spec.

Rules:
- Keep it short, skimmable, and dated.
- Prefer facts/evidence; label hypotheses.
- Don’t store secrets/credentials; don’t paste logs with sensitive data.

### 2026-02-23 — Initial intent capture
- Goal: replicate the “little experiment” in this repo, but using **Google APIs** for:
  - **STT / speech-to-text** (unknown which Google API to use yet)
  - **TTS / text-to-speech** (already used elsewhere)
- Existing TTS: `speaks.sh` uses `/Users/christian.gintenreiter/dev/speak-to-me` (Google-TTS-based).
- STT options noted:
  - Candidate: **Google Cloud Speech-to-Text API** (most common/default choice).
  - Tried: **Chirp** experiment (`/Users/christian.gintenreiter/dev/speak-to-me/experiments/chirp_speech_recognition.py`) → didn’t work as expected.
  - Alternative idea: “Google Interactions” / multimodal interactions (hypothesis: could enable a more capable interaction loop than plain STT).
- Reference playground: `/Users/christian.gintenreiter/dev-external/voxmlx` hosts an `sst_playground` that does:
  - `STT → DSPy/LLM-calling based on spoken input → TTS` response loop
  - Note: intended to move toward `../my-speech-local/` (per that project’s IDEA.md).
- Prior art: Mistral Voxtral online API worked well; realtime streaming transcription integration exists in:
  - `/Users/christian.gintenreiter/dev/elix-live-chat/lib/live_ai_chat/mistral/realtime_transcription_ws.ex`

### Open questions (not for top-of-doc)
- What is the *minimum viable* experiment we want here (batch transcription vs streaming; single file vs microphone)?
- Which Google offering is the intended target (Cloud STT v2, Gemini audio models, “Interactions”)?
- What is the success criterion (latency, accuracy, streaming partials, diarization, cost)?
