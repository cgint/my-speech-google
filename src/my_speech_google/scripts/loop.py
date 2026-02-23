from __future__ import annotations

import argparse
import sys
import threading

from ..audio import MicStreamer
from ..dspy_responder import DspyConfig, respond_with_dspy
from ..google_stt import GoogleCloudSttV2, SttConfig, default_project_id
from ..google_tts import speak


def main() -> None:
    p = argparse.ArgumentParser(
        description="Full loop: mic STT -> DSPy -> TTS (Google backends)"
    )
    p.add_argument("--project", help="GCP project id (or set GOOGLE_CLOUD_PROJECT)")
    p.add_argument("--location", default="eu", help="STT location (e.g. eu, us, europe-west1)")
    p.add_argument("--lang", default="en-US", help="Language code")
    p.add_argument("--model", default="chirp_3", help="STT model id")
    p.add_argument(
        "--tts-prefer",
        choices=["gemini", "cloud"],
        default="gemini",
        help="TTS backend preference",
    )
    p.add_argument(
        "--dspy-model",
        default="gemini/gemini-2.5-flash",
        help="DSPy LM model id",
    )
    p.add_argument(
        "--context-hints",
        default="",
        help="Optional DSPy context hints (persona / constraints)",
    )
    p.add_argument("--once", action="store_true", help="Run one turn and exit")
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

    dspy_cfg = DspyConfig(model=args.dspy_model, context_hints=args.context_hints)

    while True:
        mic = MicStreamer()

        def wait_stop() -> None:
            input("\n[loop] Speak now... press ENTER to stop.\n")
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
                    print(
                        f"\r[partial] {last_partial[:160]}{'...' if len(last_partial) > 160 else ''} ",
                        end="",
                        flush=True,
                    )
        except KeyboardInterrupt:
            mic.stop()

        transcript = final_text or last_partial
        transcript = (transcript or "").strip()
        if not transcript:
            print("[loop] Empty transcript; try again.")
            if args.once:
                return
            continue

        response = respond_with_dspy(text=transcript, cfg=dspy_cfg)
        print(f"[dspy] {response}")

        # Speak back
        speak(response, prefer=args.tts_prefer)

        if args.once:
            return

        again = input("\n[loop] Press ENTER to record again, or type 'q' to quit: ")
        if again.strip().lower() in {"q", "quit", "exit"}:
            return


if __name__ == "__main__":
    main()
