from __future__ import annotations

import argparse

from ..google_tts import speak


def main() -> None:
    p = argparse.ArgumentParser(description="Text-to-speech using Google backends")
    p.add_argument("-t", "--text", required=True, help="Text to speak")
    p.add_argument(
        "--prefer",
        choices=["gemini", "cloud"],
        default="gemini",
        help="Preferred backend (gemini live streaming if API key exists; otherwise cloud)",
    )
    p.add_argument("--save-wav", help="If set, write output WAV here")
    args = p.parse_args()

    speak(args.text, prefer=args.prefer, save_wav=args.save_wav)


if __name__ == "__main__":
    main()
