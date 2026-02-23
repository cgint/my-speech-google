from __future__ import annotations

import argparse
import sys
import threading

from ..audio import MicStreamer
from ..google_stt import GoogleCloudSttV2, SttConfig, default_project_id


def main() -> None:
    p = argparse.ArgumentParser(description="Streaming mic transcription (Google Cloud STT v2)")
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

    mic = MicStreamer()

    def wait_stop() -> None:
        input("\n[stt] Recording... press ENTER to stop.\n")
        mic.stop()

    stopper = threading.Thread(target=wait_stop, daemon=True)
    stopper.start()

    last_partial = ""
    final_text = ""

    try:
        for text, is_final in stt.streaming_recognize(audio_chunks=mic.iter_chunks()):
            if not text.strip():
                continue
            if is_final:
                final_text = text
                print(f"\n[final] {text}\n")
            else:
                last_partial = text
                print(f"\r[partial] {last_partial[:160]}{'...' if len(last_partial) > 160 else ''} ", end="", flush=True)
    except KeyboardInterrupt:
        mic.stop()

    if not final_text and last_partial:
        print(f"\n[partial-as-final] {last_partial}\n")


if __name__ == "__main__":
    main()
