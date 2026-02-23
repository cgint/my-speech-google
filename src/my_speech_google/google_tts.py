from __future__ import annotations

import asyncio
import os
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator, Iterable

from .audio import AudioFormat, play_pcm16, write_wav_pcm16


@dataclass(frozen=True)
class TtsAudio:
    pcm16: bytes
    fmt: AudioFormat


def _get_gemini_api_key() -> str | None:
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")


def cloud_tts_synthesize(text: str, *, voice_name: str = "en-US-Neural2-F") -> TtsAudio:
    """Synthesize using Google Cloud Text-to-Speech.

    Returns PCM16 audio wrapped in a WAV container is *not* guaranteed; we return
    raw PCM16 + format for consistent playback.
    """

    from google.cloud import texttospeech  # lazy import

    client = texttospeech.TextToSpeechClient()

    response = client.synthesize_speech(
        input=texttospeech.SynthesisInput(text=text),
        voice=texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name=voice_name,
        ),
        audio_config=texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.LINEAR16,
            sample_rate_hertz=16_000,
        ),
    )

    # Cloud TTS returns raw LINEAR16 bytes (no WAV header).
    return TtsAudio(pcm16=response.audio_content, fmt=AudioFormat(16_000, 1))


async def gemini_live_tts_chunks(
    *,
    text: str,
    voice_name: str = "Puck",
    model_id: str = "gemini-live-2.5-flash-preview",
) -> AsyncIterator[bytes]:
    """Stream audio chunks from Gemini Live API.

    Chunks are PCM16, typically 24kHz mono.
    """

    api_key = _get_gemini_api_key()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY/GOOGLE_API_KEY not set")

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=api_key, http_options={"api_version": "v1alpha"})

    config = types.LiveConnectConfig(
        system_instruction="Read the user's text out loud exactly as is in natural speech. No greetings. No intro.",
        response_modalities=[types.Modality.AUDIO],
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice_name)
            )
        ),
        # Also request an output transcription for debugging/verification.
        output_audio_transcription=types.AudioTranscriptionConfig(),
    )

    async with client.aio.live.connect(model=model_id, config=config) as session:
        await session.send_realtime_input(text=text)

        async for msg in session.receive():
            if msg.server_content and msg.server_content.model_turn:
                parts = msg.server_content.model_turn.parts or []
                for part in parts:
                    if part.inline_data and (part.inline_data.mime_type or "").startswith("audio"):
                        if part.inline_data.data:
                            yield part.inline_data.data

            if msg.server_content and msg.server_content.turn_complete:
                break


async def gemini_live_tts_synthesize(text: str, *, voice_name: str = "Puck") -> TtsAudio:
    chunks: list[bytes] = []
    async for c in gemini_live_tts_chunks(text=text, voice_name=voice_name):
        chunks.append(c)

    pcm16 = b"".join(chunks)
    return TtsAudio(pcm16=pcm16, fmt=AudioFormat(24_000, 1))


def speak(text: str, *, prefer: str = "gemini", save_wav: str | Path | None = None) -> TtsAudio:
    text = text.strip()
    if not text:
        raise ValueError("text is empty")

    audio: TtsAudio

    if prefer == "gemini" and _get_gemini_api_key():
        audio = asyncio.run(gemini_live_tts_synthesize(text))
    elif prefer in ("cloud", "gemini"):
        audio = cloud_tts_synthesize(text)
    else:
        raise ValueError("prefer must be 'gemini' or 'cloud'")

    if save_wav is not None:
        write_wav_pcm16(save_wav, pcm16=audio.pcm16, fmt=audio.fmt)

    play_pcm16(pcm16=audio.pcm16, fmt=audio.fmt)
    return audio
