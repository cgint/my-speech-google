# What i want to be done in this repository
I want to do the same little experiment but with Google's APIs for SST and TTS.

TTS we already use in speaks.sh which uses /Users/christian.gintenreiter/dev/speak-to-me which is based on a google-tts.

For SST I do not know yet which API from Google to use but found e.g. "Google Cloud's Speech-to-Text API" which seems to be the most popular one.
- I tried Chirp (see /Users/christian.gintenreiter/dev/speak-to-me/experiments/chirp_speech_recognition.py) but it did not work as expected.
- Google Interactions also sounds intriguing as it allows different modalities to be given and asked for in return.

IMPORTANT: It might be that we can do something similar with Interaction


# Appendix

## Reference to playground for SST-DSPy-TTS
/Users/christian.gintenreiter/dev-external/voxmlx currently hosts a sst_playground.
That is actually now a `SST -> DSPy-LLM-Calling based on spoken input -> TTS` to respond with speech again.

IT is meant to go to ../my-speech-local/ see IDEA.md there.                                                                                                                  

## Reference to Mistral-Voxtral-Online-API
I already tried out Mistral-Voxtral-Online-API which works great.
See /Users/christian.gintenreiter/dev/elix-live-chat/lib/live_ai_chat/mistral/realtime_transcription_ws.ex for how it was integrated in the elix-live-chat project with streaming audio to it and receiving the transcription in realtime.
