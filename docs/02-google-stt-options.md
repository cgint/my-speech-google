# Google STT options (Speech-to-Text)

## Option A — Google Cloud Speech-to-Text v2 (speech_v2)

**Evidence in existing experiments:**
- `speak-to-me/experiments/chirp_speech_recognition.py` uses:
  - `from google.cloud import speech_v2`
  - regional endpoint via `ClientOptions(api_endpoint=f"{location}-speech.googleapis.com")`
  - `RecognitionConfig(... model="chirp_3" ...)`
  - a **Recognizer** resource (`projects/{project}/locations/{location}/recognizers/{id}`), created if missing.
  - `RecognizeRequest(... content=audio_content)` (non-streaming recognize).

**What this implies / why it’s attractive**
- It’s a dedicated STT API (clear contract: audio → transcript).
- Auth uses Google Cloud credentials (ADC / service account), consistent with Cloud TTS.

**Risks / gotchas (based on the experiment file + typical GCP patterns)**
- You must pick the right **location** and endpoint. The experiment hardcodes `europe-west1`.
- Recognizer lifecycle is an extra moving piece (create/list/permissions).
- Model naming is confusing (`chirp` vs `chirp_3` in the experiment) → likely source of “did not work as expected”.
  - Hypothesis: inconsistent model config between Recognizer defaults vs request config.

**Open items to validate**
- Which models are available/allowed in your project+region.
- Whether we need **streaming** recognition (partials) and what the v2 streaming API surface looks like in Python.

---

## Option B — Gemini audio models ("audio-native" / Live API)

**Evidence in existing experiments:**
- `speak-to-me/experiments/gemini_live_audio.py` connects to a Live session using `google-genai`:
  - `client = genai.Client(api_key=GEMINI_API_KEY, http_options={"api_version": "v1alpha"})`
  - `client.aio.live.connect(model=..., config=LiveConnectConfig(... response_modalities=[AUDIO]))`
  - receives streaming **audio** chunks back (TTS-like output).

**How this could be used for STT**
- Hypothesis (needs confirmation by testing): Gemini can take **audio input** and return **text** (and/or audio) in a single session.
- Upside: could unify STT + reasoning + TTS in one system.

**Risks / tradeoffs**
- It’s not “pure STT”; behavior depends on prompting and model behavior.
- Might be harder to guarantee: accuracy, “no hallucination”, strict verbatim transcription.
- Uses API key auth (different from GCP ADC).

---

## Option C — “Google Interactions” / multimodal interactions

**Current state:** mentioned as intriguing in the idea doc, but not yet pinned to a specific API/product.

**Critical note:** before investing time here, we should clarify:
- What exact Google product/API is meant.
- Whether it supports the *specific loop* we want (real-time mic → text partials → tool calls → audio response).

---

## Recommendation for a first iteration (proposal)

To de-risk quickly, choose one:

1) **Deterministic baseline:** Google Cloud Speech-to-Text v2, file-based recognize first.
2) **Interactive baseline:** Gemini Live session with audio input/output if we value “conversation feel” over strict STT.

If you tell me which dimension you care about first (accuracy/verbatim vs interactive loop), I’ll bias the MVP proposal accordingly.
