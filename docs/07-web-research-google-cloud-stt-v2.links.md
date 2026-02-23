> [!NOTE]
> This is raw web-research output. Some URLs in here were incorrect.
> Prefer validated links:
> - `./07e-validated-google-cloud-stt-links.md`

I will research the latest Google Cloud Speech-to-Text v2 documentation and Python code samples for streaming recognition, focusing on recognizers, regional endpoints, and Chirp model identifiers.
I will verify the official documentation URLs and research the specific client options required for regional endpoints in Speech-to-Text v2.
As of early 2026, using **Google Cloud Speech-to-Text v2** (`speech_v2`) for streaming recognition in Python involves several key architectural shifts from v1, most notably the introduction of **Recognizers** and **Regional Endpoints**.

### 1. Key Concepts in v2

*   **Recognizers**: In v1, you passed all configuration (language, model, etc.) with every request. In v2, you create a "Recognizer" resource once. This resource acts as a stored configuration template. You then reference this recognizer by name in your streaming requests.
*   **Regional Endpoints**: v2 is fully regionalized. To ensure data residency, you must specify a regional endpoint (e.g., `us-central1`) both in your client initialization and in the recognizer's resource path.
*   **Chirp (Large Speech Models)**: Chirp is Google's next-generation universal speech model. In v2, you specifically use identifiers like `chirp`, `chirp_2`, or `chirp_3` to leverage these high-accuracy, multi-lingual models.

---

### 2. Python Code Sample: `streaming_recognize`

This sample demonstrates how to initialize a regional client and perform a streaming recognition request using a Chirp model.

```python
import os
from google.api_core.client_options import ClientOptions
from google.cloud import speech_v2

# Configuration
PROJECT_ID = "your-project-id"
LOCATION = "us-central1"  # Regional endpoint
RECOGNIZER_ID = "my-chirp-recognizer" # Must exist in the project/location

def streaming_recognize():
    # 1. Setup Client with Regional Endpoint
    # Important: The api_endpoint must match the location of your recognizer
    client_options = ClientOptions(
        api_endpoint=f"{LOCATION}-speech.googleapis.com"
    )
    client = speech_v2.SpeechClient(client_options=client_options)

    # 2. Resource Path for the Recognizer
    recognizer_path = f"projects/{PROJECT_ID}/locations/{LOCATION}/recognizers/{RECOGNIZER_ID}"

    # 3. Streaming Configuration
    # Note: In V2, you can still override some settings here if needed, 
    # but primarily it points to the pre-configured Recognizer.
    config = speech_v2.StreamingRecognitionConfig()

    def request_generator():
        # First request MUST contain the configuration
        yield speech_v2.StreamingRecognizeRequest(
            recognizer=recognizer_path,
            streaming_config=config
        )
        
        # Subsequent requests contain the audio data (simulated here)
        # In a real app, read from a microphone or stream source
        with open("audio_clip.wav", "rb") as audio_file:
            while chunk := audio_file.read(4096):
                yield speech_v2.StreamingRecognizeRequest(audio=chunk)

    # 4. Perform Streaming Call
    responses = client.streaming_recognize(requests=request_generator())

    for response in responses:
        for result in response.results:
            print(f"Transcript: {result.alternatives[0].transcript}")
            print(f"Is Final: {result.is_final}")

if __name__ == "__main__":
    streaming_recognize()
```

---

### 3. Model Identifiers (Chirp)

When creating or using a Recognizer, specify the `model` field. Chirp models are exclusive to the v2 API:
*   `chirp`: The standard high-accuracy large speech model.
*   `chirp_2`: The second generation, offering better performance for short-form audio and improved latency.
*   `chirp_3`: The latest iteration (as of 2025/2026), optimized for extreme accuracy across 100+ languages.

---

### 4. Official Documentation & URLs

*   **Google Cloud STT v2 Overview**: [cloud.google.com/speech-to-text/v2/docs](https://cloud.google.com/speech-to-text/v2/docs)
*   **Python Client Reference (v2)**: [google-cloud-speech v2 Reference](https://cloud.google.com/python/docs/reference/speech/latest/google.cloud.speech_v2.services.speech.SpeechClient)
*   **Streaming Recognize V2 Specifics**: [Streaming Recognition Guide](https://cloud.google.com/speech-to-text/v2/docs/streaming-recognition)
*   **Chirp Model Details**: [Chirp Model Documentation](https://cloud.google.com/speech-to-text/v2/docs/chirp-model)

### 5. Summary of Regional API Endpoints
| Region | API Endpoint |
| :--- | :--- |
| **Global** | `speech.googleapis.com` |
| **US Central** | `us-central1-speech.googleapis.com` |
| **Europe West** | `europe-west1-speech.googleapis.com` |
| **Multi-Region US** | `us-speech.googleapis.com` |
| **Multi-Region EU** | `eu-speech.googleapis.com` |
