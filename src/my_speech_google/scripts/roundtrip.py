from __future__ import annotations

import argparse
import sys
from pathlib import Path

from ..google_stt import GoogleCloudSttV2, SttConfig, default_project_id
from ..google_tts import cloud_tts_synthesize
from ..audio import write_wav_pcm16


def main() -> None:
    p = argparse.ArgumentParser(
        description="Roundtrip test: Cloud TTS -> WAV -> Cloud STT v2 (file recognize)"
    )
    p.add_argument("-t", "--text", required=True, help="Text to synthesize")
    p.add_argument("--out", default="./out/roundtrip.wav", help="Output wav path")
    p.add_argument("--project", help="GCP project id (or set GOOGLE_CLOUD_PROJECT)")
    p.add_argument("--location", default="eu", help="STT location")
    p.add_argument("--lang", default="en-US", help="Language code")
    p.add_argument("--model", default="chirp_3", help="STT model id")
    args = p.parse_args()

    project = args.project or default_project_id()
    if not project:
        print("Error: set GOOGLE_CLOUD_PROJECT (or pass --project)", file=sys.stderr)
        raise SystemExit(2)

    audio = cloud_tts_synthesize(args.text)
    out_path = Path(args.out)
    write_wav_pcm16(out_path, pcm16=audio.pcm16, fmt=audio.fmt)
    print(f"[roundtrip] wrote {out_path}")

    stt = GoogleCloudSttV2(
        SttConfig(
            project_id=project,
            location=args.location,
            language_codes=(args.lang,),
            model=args.model,
        )
    )

    transcript = stt.recognize_file(out_path)
    print("[roundtrip] transcript:")
    print(transcript)


if __name__ == "__main__":
    main()
