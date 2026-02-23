from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence

from google.api_core.client_options import ClientOptions
from google.cloud import speech_v2

from .audio import AudioFormat, PCM16_16KHZ_MONO


def default_project_id() -> str | None:
    return os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("VERTEXAI_PROJECT")


@dataclass(frozen=True)
class SttConfig:
    project_id: str
    location: str = "eu"  # multi-region endpoint
    recognizer_id: str = "_"  # implicit recognizer by default
    language_codes: tuple[str, ...] = ("en-US",)
    model: str = "chirp_3"


class GoogleCloudSttV2:
    def __init__(self, cfg: SttConfig):
        self._cfg = cfg
        self._client = speech_v2.SpeechClient(
            client_options=ClientOptions(api_endpoint=f"{cfg.location}-speech.googleapis.com")
        )

    @property
    def recognizer(self) -> str:
        parent = f"projects/{self._cfg.project_id}/locations/{self._cfg.location}"
        return f"{parent}/recognizers/{self._cfg.recognizer_id}"

    def recognize_file(self, wav_path: str | Path) -> str:
        wav_path = Path(wav_path)
        content = wav_path.read_bytes()

        config = speech_v2.RecognitionConfig(
            auto_decoding_config=speech_v2.AutoDetectDecodingConfig(),
            language_codes=list(self._cfg.language_codes),
            model=self._cfg.model,
        )

        request = speech_v2.RecognizeRequest(
            recognizer=self.recognizer,
            config=config,
            content=content,
        )

        response = self._client.recognize(request=request)

        transcripts: list[str] = []
        for result in response.results:
            if result.alternatives:
                transcripts.append(result.alternatives[0].transcript)

        return "\n".join(t for t in transcripts if t.strip())

    def streaming_recognize(
        self,
        *,
        audio_chunks: Iterable[bytes],
        fmt: AudioFormat = PCM16_16KHZ_MONO,
        interim_results: bool = True,
    ) -> Iterator[tuple[str, bool]]:
        """Yield (text, is_final) tuples."""

        if fmt.sample_rate_hz != 16_000 or fmt.channels != 1:
            # Keep this strict for first prototype to avoid format mismatch pain.
            raise ValueError(
                f"only 16kHz mono supported for now, got {fmt.sample_rate_hz}Hz ch={fmt.channels}"
            )

        # NOTE: for raw PCM streaming we should use explicit decoding.
        # Auto decoding is great for containers (wav/flac) but less clear for raw streams.
        explicit = speech_v2.ExplicitDecodingConfig(
            encoding=speech_v2.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=fmt.sample_rate_hz,
            audio_channel_count=fmt.channels,
        )

        recognition_config = speech_v2.RecognitionConfig(
            explicit_decoding_config=explicit,
            language_codes=list(self._cfg.language_codes),
            model=self._cfg.model,
        )

        streaming_config = speech_v2.StreamingRecognitionConfig(
            config=recognition_config,
            interim_results=interim_results,
        )

        def reqs() -> Iterator[speech_v2.StreamingRecognizeRequest]:
            yield speech_v2.StreamingRecognizeRequest(
                recognizer=self.recognizer,
                streaming_config=streaming_config,
            )
            for chunk in audio_chunks:
                if not chunk:
                    continue
                yield speech_v2.StreamingRecognizeRequest(audio=chunk)

        for resp in self._client.streaming_recognize(requests=reqs()):
            for result in resp.results:
                if not result.alternatives:
                    continue
                text = result.alternatives[0].transcript
                yield text, bool(result.is_final)
