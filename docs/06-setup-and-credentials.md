# Setup and credentials (notes)

This doc captures the credential/config surface implied by the existing experiments.

## If we use Google Cloud APIs (Speech-to-Text v2 / Text-to-Speech)

### Authentication

Evidence from `standard_tts.py` + `chirp_speech_recognition.py`:

- Uses Google Cloud client libraries (`google.cloud.*`) → typically relies on **Application Default Credentials (ADC)**.
- Common env vars you may use:
  - `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`
  - `GOOGLE_CLOUD_PROJECT=...` (or `VERTEXAI_PROJECT` is checked in the Chirp script)

> Note: per repo safety rules, we won’t edit `.env` files; we’ll document required env vars and you set them.

### APIs to enable (project-side)

- Cloud Speech-to-Text
- Cloud Text-to-Speech

(Exact enablement steps are intentionally not written here yet; we’ll add them once we confirm the chosen APIs and whether you use gcloud or console.)

### Region / endpoint

Evidence from Chirp experiment:
- STT v2 may require using a **regional endpoint** like:
  - `{location}-speech.googleapis.com` (example location used: `europe-west1`)

Critical: region choice impacts availability and permissions.

## If we use Gemini API (google-genai)

Evidence from `gemini_live_audio.py`:

- Uses `GEMINI_API_KEY` for auth.
- Some calls set `http_options={"api_version": "v1alpha"}`.
- Model IDs are explicit strings (preview IDs).

Risks:
- Preview model names can change; we should encapsulate them in one place in this repo when implementing.

## Audio format conventions to settle early

We should decide and document:
- sample rate (16k vs 24k)
- channels (mono)
- encoding (PCM s16le vs WAV container)

Reason: STT/TTS endpoints often require strict format matching; many “it doesn’t work” issues are audio-format mismatches.
