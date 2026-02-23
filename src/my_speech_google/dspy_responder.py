from __future__ import annotations

import os
from dataclasses import dataclass


def _gemini_api_key() -> str | None:
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")


@dataclass(frozen=True)
class DspyConfig:
    model: str = "gemini/gemini-2.5-flash"
    api_key: str | None = None
    context_hints: str = ""


def respond_with_dspy(*, text: str, cfg: DspyConfig | None = None) -> str:
    """Transform transcript text into a response using DSPy.

    If no API key is available, this falls back to a simple echo so the overall
    loop remains usable.
    """

    text = text.strip()
    if not text:
        return "(no transcript)"

    cfg = cfg or DspyConfig()
    api_key = cfg.api_key or _gemini_api_key()

    if not api_key:
        return f"You said: {text}"

    import dspy

    # Configure LM.
    lm = dspy.LM(model=cfg.model, api_key=api_key, cache=True)
    dspy.settings.configure(lm=lm)

    class SpeechResponder(dspy.Signature):
        """Respond to the user's spoken text briefly and helpfully."""

        context_hints: str = dspy.InputField(desc="Optional context / persona hints")
        transcript: str = dspy.InputField(desc="What the user said")
        response: str = dspy.OutputField(desc="What we should say back")

    program = dspy.ChainOfThought(SpeechResponder)
    out = program(context_hints=cfg.context_hints, transcript=text)

    result = getattr(out, "response", None)
    if not isinstance(result, str) or not result.strip():
        return f"You said: {text}"

    return result.strip()
