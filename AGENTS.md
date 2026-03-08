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
- Do intermadiary commits of all md and source files to git (do NOT push) so that you have some history
- Tech Stack is Elixir ecosystem only as in sst_playground (use asks.sh to find out information about that stack)

### 2026-02-23 — Initial intent capture
- Goal: replicate the “little experiment” in this repo, but using **Google APIs** for:
  - **STT / speech-to-text** (unknown which Google API to use yet)
  - **TTS / text-to-speech** (already used elsewhere)
- **Stack constraint (explicit):** the main stack is **Elixir** (Phoenix/LiveView), aligned with `/Users/cgint/dev-external/voxmlx/stt_playground`.
  - We should be able to **reuse ~80%+** of that codebase/architecture **as-is**.
  - Only the integrated **STT** and **TTS** tech should change to **Google APIs** (keep the rest of the flow intact).
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

### 2026-03-08 — STT comparison harness + benchmark (notes)

We built a small, repeatable comparison harness (file-in → text-out):
- Scripts: `./stt_file_google.py`, `./stt_file_gemini.py`, runner `./bench_compare.sh`
- Benchmark WAV set: `bench_audio/` (see `bench_audio/manifest.tsv`)

Durable details (exact transcripts, timings, caveats, next steps):
- **`docs/stt-benchmark-findings.md`**

Key takeaways to remember
- Google STT v2 batch (`recognize`) is fastest on short clips; Gemini was slower but sometimes preserved German domain-ish tokens better.
- Do not judge real-time UX from “stream replay” timings (startup overhead dominates short files).
- Plan for a context-aware post-processing layer (normalization + domain dictionary + optional gated LLM correction).

### Open questions (not for top-of-doc)
- What is the *minimum viable* experiment we want here (batch transcription vs streaming; single file vs microphone)?
- Which Google offering is the intended target (Cloud STT v2, Gemini audio models, “Interactions”)?
- What is the success criterion (latency, accuracy, streaming partials, diarization, cost)?
