#!/usr/bin/env python3
"""stt_file_gemini.py — Audio file to text using a Gemini multimodal model.

This is a tiny side prototype meant for quick comparisons against Google Cloud STT.

How it works:
- Upload audio via the Gemini File API (google-genai SDK)
- Ask the model to return a plain transcript (no timestamps / no analysis)

Output:
- Transcript is printed to STDOUT (plain text only).
- Timing / diagnostics are printed to STDERR.

Auth:
- Requires GEMINI_API_KEY (or GOOGLE_API_KEY)

Model:
- Defaults to: gemini-3.1-flash-lite-preview
- Override with --model
"""

from __future__ import annotations

import argparse
import mimetypes
import os
import sys
import time
from pathlib import Path
from typing import Optional


def _env(name: str, default: Optional[str] = None) -> Optional[str]:
    v = os.environ.get(name)
    return v if v is not None and v.strip() != "" else default


def api_key() -> Optional[str]:
    return _env("GEMINI_API_KEY") or _env("GOOGLE_API_KEY")


def guess_mime_type(path: Path) -> str:
    # Best-effort. You can override via --mime-type.
    mt, _enc = mimetypes.guess_type(str(path))
    if mt:
        return mt

    ext = path.suffix.lower().lstrip(".")
    return {
        "wav": "audio/wav",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "mp4": "audio/mp4",
        "ogg": "audio/ogg",
        "opus": "audio/opus",
        "flac": "audio/flac",
    }.get(ext, "application/octet-stream")


def main() -> None:
    p = argparse.ArgumentParser(description="File transcription using Gemini multimodal audio input.")
    p.add_argument("audio_path", help="Path to audio file")
    p.add_argument(
        "--model",
        default="gemini-3.1-flash-lite-preview",
        help="Gemini model id (default: gemini-3.1-flash-lite-preview)",
    )
    p.add_argument(
        "--mime-type",
        default=None,
        help="Override detected MIME type (e.g. audio/mpeg, audio/wav)",
    )

    args = p.parse_args()

    key = api_key()
    if not key:
        print("Error: set GEMINI_API_KEY (or GOOGLE_API_KEY).", file=sys.stderr)
        raise SystemExit(2)

    audio_path = Path(args.audio_path)
    if not audio_path.exists():
        print(f"Error: file not found: {audio_path}", file=sys.stderr)
        raise SystemExit(2)

    mime_type = args.mime_type or guess_mime_type(audio_path)

    # Lazy imports so the script still shows a helpful API key error without SDK installed.
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=key)

    prompt = (
        "Transcribe the provided audio file. "
        "Return ONLY the raw transcript text. "
        "No timestamps. No speaker labels. No commentary."
    )

    t0 = time.perf_counter()

    try:
        f = client.files.upload(file=str(audio_path), config=types.UploadFileConfig(mime_type=mime_type))

        resp = client.models.generate_content(
            model=args.model,
            contents=[
                prompt,
                types.Part.from_uri(file_uri=f.uri, mime_type=f.mime_type or mime_type),
            ],
            config=types.GenerateContentConfig(
                temperature=0.0,
            ),
        )

        # google-genai response convenience: prefer resp.text when present.
        text = (getattr(resp, "text", None) or "").strip()
        if not text:
            # Fallback to manual extraction (defensive).
            parts = []
            try:
                for cand in resp.candidates or []:
                    content = cand.content
                    if not content or not content.parts:
                        continue
                    for part in content.parts:
                        if getattr(part, "text", None):
                            parts.append(part.text)
            except Exception:
                pass
            text = "\n".join(p.strip() for p in parts if p and p.strip()).strip()

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        raise SystemExit(1)

    dt_ms = (time.perf_counter() - t0) * 1000.0
    print(f"[gemini] model={args.model} time_ms={dt_ms:.1f} mime_type={mime_type}", file=sys.stderr)

    sys.stdout.write(text + "\n")


if __name__ == "__main__":
    main()
