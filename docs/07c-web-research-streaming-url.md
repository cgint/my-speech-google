I will now perform a Google search to find the official Google Cloud Speech-to-Text documentation for streaming recognition.

The official Google Cloud Speech-to-Text documentation page for streaming recognition is:

**URL:** https://cloud.google.com/speech-to-text/docs/streaming-recognition

### **Summary of Streaming Recognition**
Google Cloud Speech-to-Text (STT) provides streaming recognition to transcribe audio in real-time. This is essential for applications like live captioning, voice-activated assistants, and real-time meeting transcriptions.

#### **Key Technical Details:**
*   **gRPC Exclusive:** Streaming speech recognition is **only available via gRPC**. It is not supported by REST APIs.
*   **Bidirectional Streaming:** The process involves opening a bidirectional gRPC stream. You send audio data chunks to the API and receive a series of response messages in return.
*   **Interim vs. Final Results:** The API can return "interim results" (hypotheses that may change as more audio is processed) and "final results" (once the API has high confidence in the transcript for a segment).
*   **Time Limit:** Individual streams are limited to approximately **5 minutes** of audio. For longer sessions, you must start a new stream.
*   **Models:** It supports standard models and the advanced **Chirp 3** model (part of the Gemini era of speech models), which offers improved accuracy across 85+ languages.
*   **Configuration:** You control the behavior using the `StreamingRecognitionConfig` object, where you can specify parameters like `single_utterance` (to stop after a single command) and `interim_results`.

**Sources:**
- [Official Google Cloud Documentation: Streaming Recognition](https://cloud.google.com/speech-to-text/docs/streaming-recognition)
- [Google Cloud Speech-to-Text V2 API Reference](https://cloud.google.com/speech-to-text/v2/docs/reference/rpc/google.cloud.speech.v2)
