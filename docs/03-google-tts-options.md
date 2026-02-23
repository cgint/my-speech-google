# Google TTS options (Text-to-Speech)

## Option A — Google Cloud Text-to-Speech API (google.cloud.texttospeech)

**Evidence in existing experiments:**
- `speak-to-me/experiments/standard_tts.py` uses:
  - `from google.cloud import texttospeech`
  - `TextToSpeechClient()`
  - voice selection (example): `en-US-Neural2-F`
  - output: `LINEAR16` (WAV/PCM)

**Pros**
- Purpose-built TTS; stable API contract.
- Auth aligns with Google Cloud STT if we choose Speech-to-Text v2.

**Cons / risks**
- Requires GCP project setup + enabling the API + credentials.
- Voice/model availability varies by region/account.

---

## Option B — Gemini audio generation (google-genai)

**Evidence in existing experiments:**
- `speak-to-me/experiments/gemini_audio_native_modality.py`
  - uses `client.models.generate_content(... response_modalities=["AUDIO"])`
  - references model `gemini-2.5-flash-preview-tts`
- `speak-to-me/experiments/gemini_audio_server.py`
  - uses model `gemini-2.5-flash-native-audio-preview-12-2025`
  - requests `response_mime_type="audio/wav"`

**Pros**
- Potentially very natural voices + can be closer to an “agent” voice pipeline.
- Uses API key auth; can be simpler than Cloud auth if you’re not already set up.

**Cons / risks**
- Model IDs / preview availability can change.
- If we also need deterministic STT, we might end up mixing 2 auth mechanisms (API key + GCP).

---

## Practical recommendation (proposal)

- If we choose **Cloud STT v2**, prefer **Cloud TTS** first (one credential story, predictable behavior).
- If we choose an **interactive Gemini Live** approach, consider Gemini audio out to keep the entire loop in one family.
