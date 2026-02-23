# Gemini Multimodal Live API — validated notes (audio in, text out)

This is grounded in **local SDK inspection** from:
- `/Users/christian.gintenreiter/dev/speak-to-me/.venv/lib/python3.13/site-packages/google/genai/live.py`
- `/Users/christian.gintenreiter/dev/speak-to-me/.venv/lib/python3.13/site-packages/google/genai/types.py`

And linked to the public overview:
- https://ai.google.dev/gemini-api/docs/multimodal-live

## Key capability: send audio chunks

In the `google-genai` SDK, audio chunks are sent via:
- `session.send_realtime_input(media=types.Blob(...))`

Evidence (from `live.py` docstring example):
- it reads bytes and sends:
  - `media=types.Blob(data=audio_bytes, mime_type='audio/pcm;rate=16000')`

So for our repo, the *shape* is:

```python
from google import genai
from google.genai import types

# ... connect ...
await session.send_realtime_input(
  media=types.Blob(data=pcm_chunk, mime_type="audio/pcm;rate=16000")
)
```

## Enabling transcription

In `types.py`, `LiveConnectConfig` includes:
- `input_audio_transcription: Optional[AudioTranscriptionConfig]`
- `output_audio_transcription: Optional[AudioTranscriptionConfig]`

Important detail:
- `AudioTranscriptionConfig` currently has **no fields** (it’s an empty model), so enabling likely means “set it to a non-null object”.

Example intent:

```python
config = types.LiveConnectConfig(
  response_modalities=[types.Modality.TEXT],
  input_audio_transcription=types.AudioTranscriptionConfig(),
)
```

## Where transcription shows up in responses

In `types.py`, transcription appears under `LiveServerContent`:
- `input_transcription: Optional[Transcription]` (has fields: `text`, `finished`)
- `output_transcription: Optional[Transcription]`

So the receive loop should look for something like:
- `msg.server_content.input_transcription.text`

## Model-name caution (important)

The SDK example includes model IDs that mention `gemini-2.0-*`.
Per our workspace safety rules, we should **avoid gemini-2.0 model IDs**.

For this repo, we should prefer:
- `gemini-live-2.5-flash-preview` (seen in the SDK docstring example)
- or an equivalent **gemini-3** live-capable model, if/when documented.

## Why this matters for `my-speech-google`

If our goal is an *interaction loop* (STT → tool/LLM → TTS), Gemini Live can potentially provide:
- low-latency audio-in
- input transcription events
- text responses (and/or audio responses)

Tradeoff: this is not “pure STT”; it’s a multimodal model session.
