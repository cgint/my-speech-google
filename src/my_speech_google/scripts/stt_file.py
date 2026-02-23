from __future__ import annotations

import argparse
import sys

from ..google_stt import GoogleCloudSttV2, SttConfig, default_project_id


def main() -> None:
    p = argparse.ArgumentParser(description="Speech-to-text (Google Cloud STT v2) for WAV files")
    p.add_argument("wav_path", help="Path to WAV file")
    p.add_argument("--project", help="GCP project id (or set GOOGLE_CLOUD_PROJECT)")
    p.add_argument("--location", default="eu", help="STT location (e.g. eu, us, europe-west1)")
    p.add_argument("--lang", default="en-US", help="Language code")
    p.add_argument("--model", default="chirp_3", help="Model id (e.g. chirp_3)")
    args = p.parse_args()

    project = args.project or default_project_id()
    if not project:
        print("Error: set GOOGLE_CLOUD_PROJECT (or pass --project)", file=sys.stderr)
        raise SystemExit(2)

    stt = GoogleCloudSttV2(
        SttConfig(
            project_id=project,
            location=args.location,
            language_codes=(args.lang,),
            model=args.model,
        )
    )

    text = stt.recognize_file(args.wav_path)
    print(text)


if __name__ == "__main__":
    main()
