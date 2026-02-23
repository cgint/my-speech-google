# Validated links + key facts — Google Cloud Speech-to-Text (STT) v2

This note is a **reality-check** over the web-research outputs, because some URLs suggested by LLM summaries were wrong.

## What was validated (by `curl -I -L` in this environment)

### Core docs
- Overview (redirects from `/v2/...` to docs site):
  - https://docs.cloud.google.com/speech-to-text/docs

### Streaming recognition
- Streaming recognition guide:
  - https://docs.cloud.google.com/speech-to-text/docs/streaming-recognize
- Streaming recognize code samples:
  - https://docs.cloud.google.com/speech-to-text/docs/samples/speech-streaming-recognize

### Chirp models
- Chirp 3 model page:
  - https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3

### API references
- RPC reference root (v2):
  - https://docs.cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v2
- REST reference: recognize (v2):
  - https://docs.cloud.google.com/speech-to-text/docs/reference/rest/v2/projects.locations.recognizers/recognize
- REST reference: create recognizer (v2):
  - https://docs.cloud.google.com/speech-to-text/docs/reference/rest/v2/projects.locations.recognizers/create

## Evidence: implicit recognizer `recognizers/_`

From the REST reference HTML for `projects.locations.recognizers.recognize` we can directly extract:

> "The {recognizer} segment may be set to `_` to use an empty implicit Recognizer."

(Verified by fetching the page and grepping for `empty implicit Recognizer`.)

Practical meaning:
- You can call recognize against:
  - `projects/{project}/locations/{location}/recognizers/_`
- This allows “v1-like” ad-hoc usage without creating a named Recognizer resource first.

## Critical notes for our repo

- **Streaming STT requires gRPC** (typical for Google Cloud STT). Plan accordingly (Python client library vs raw REST).
- The **location/endpoint** coupling is real (recognizer path includes location; client uses `{location}-speech.googleapis.com`).
- The earlier Chirp experiment in `speak-to-me` creates/list recognizers; we can simplify early testing by using `recognizers/_` first, then introduce named recognizers if needed.
