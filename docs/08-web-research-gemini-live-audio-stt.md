> [!WARNING]
> This file is **raw web-research output** and contains inaccuracies (example: uses a `gemini-2.0-*` model ID and an `AudioTranscriptionConfig(enabled=True)` field that doesn’t exist in the locally installed SDK).
> 
> Prefer the validated note:
> - `./08b-gemini-live-api-transcription-validated.md`

I will now research the Gemini Live API (Multimodal Live API) to determine how to send audio input and receive transcription text output using the `google-genai` Python SDK.

Researching the Gemini Multimodal Live API (using the `google-genai` Python SDK) confirms that you can stream audio to the model and receive real-time transcriptions of your own speech by enabling the `input_audio_transcription` feature in the session configuration.

### Official Documentation & Resources
*   **Multimodal Live API Overview:** [https://ai.google.dev/gemini-api/docs/multimodal-live](https://ai.google.dev/gemini-api/docs/multimodal-live)
*   **Gemini API SDK (google-genai):** [https://github.com/googleapis/python-genai](https://github.com/googleapis/python-genai)
*   **Python SDK Live Client API Reference:** [google.genai.Client.aio.live](https://github.com/googleapis/python-genai/blob/main/google/genai/live.py)

### Minimal Code Example
The following script demonstrates how to connect to the Live API, configure it for transcription, and print the transcribed text as you send audio bytes.

```python
import asyncio
import os
from google import genai
from google.genai.types import LiveConnectConfig, AudioTranscriptionConfig

# 1. Initialize the GenAI Client
# Set GOOGLE_API_KEY environment variable or pass it here
client = genai.Client(api_key=os.environ.get("GOOGLE_API_KEY"), http_options={'api_version': 'v1alpha'})

async def stream_audio_and_get_transcription():
    model_id = "gemini-2.0-flash-exp" # Use a model supporting Multimodal Live API

    # 2. Configure the session
    # We enable 'input_audio_transcription' to get text of what we say
    config = LiveConnectConfig(
        response_modalities=["TEXT"], # The model responds with text
        input_audio_transcription=AudioTranscriptionConfig(enabled=True)
    )

    async with client.aio.live.connect(model=model_id, config=config) as session:
        print("Connected to Gemini Live. Sending dummy audio...")

        # 3. Task to receive server events (Transcriptions & Model Responses)
        async def receive_events():
            async for event in session.receive():
                # Check for transcription of YOUR input audio
                if event.input_audio_transcription:
                    print(f"[User Transcript]: {event.input_audio_transcription.text}")
                
                # Check for the model's text response
                if event.server_content and event.server_content.model_turn:
                    parts = event.server_content.model_turn.parts
                    for part in parts:
                        if part.text:
                            print(f"[Gemini]: {part.text}")

        # 4. Task to send audio data
        async def send_audio():
            # In a real app, read from a mic (e.g., via PyAudio)
            # Audio must be 16-bit PCM, 16kHz, Mono
            sample_rate = 16000
            silence_chunk = b'\x00\x00' * (sample_rate // 10) # 100ms of silence
            
            for _ in range(50): # Send 5 seconds of "audio"
                await session.send(input=silence_chunk, end_of_turn=False)
                await asyncio.sleep(0.1)
            
            await session.send(input=b'', end_of_turn=True)

        await asyncio.gather(receive_events(), send_audio())

if __name__ == "__main__":
    asyncio.run(stream_audio_and_get_transcription())
```

### Key Technical Requirements
1.  **Audio Format:** The API expects **Raw PCM, 16-bit, Little-Endian, 16kHz, Mono**.
2.  **Configuration:** You must set `input_audio_transcription=AudioTranscriptionConfig(enabled=True)` inside your `LiveConnectConfig`.
3.  **Event Handling:** Transcriptions are returned in the `input_audio_transcription` field of the server events, separate from the model's generated response (`server_content`).
4.  **Library:** Use the newer `google-genai` library (`pip install google-genai`) rather than the older `google-generativeai`.
