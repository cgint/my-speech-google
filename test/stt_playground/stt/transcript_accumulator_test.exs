defmodule SttPlayground.STT.TranscriptAccumulatorTest do
  use ExUnit.Case, async: true

  alias SttPlayground.STT.TranscriptAccumulator

  test "stable_text only grows on final results; interims can jump" do
    s = TranscriptAccumulator.new()

    # A few volatile interims:
    s = TranscriptAccumulator.ingest(s, "okay", false)
    s = TranscriptAccumulator.ingest(s, "okay so", false)
    s = TranscriptAccumulator.ingest(s, "so this is", false)

    assert TranscriptAccumulator.stable_text(s) == ""
    assert TranscriptAccumulator.display_text(s) == "so this is"

    # First finalized segment:
    s = TranscriptAccumulator.ingest(s, "okay so this is the Moon", true)

    assert TranscriptAccumulator.stable_text(s) == "okay so this is the Moon"
    assert TranscriptAccumulator.interim_text(s) == ""

    # More interims for the next segment:
    s = TranscriptAccumulator.ingest(s, "and", false)
    s = TranscriptAccumulator.ingest(s, "and this is", false)

    assert TranscriptAccumulator.stable_text(s) == "okay so this is the Moon"
    assert TranscriptAccumulator.display_text(s) == "okay so this is the Moon and this is"

    # Second finalized segment:
    s = TranscriptAccumulator.ingest(s, "and this is the Sun", true)

    assert TranscriptAccumulator.stable_text(s) == "okay so this is the Moon and this is the Sun"
    assert TranscriptAccumulator.display_text(s) == "okay so this is the Moon and this is the Sun"
  end

  test "does not duplicate consecutive identical final segments" do
    s = TranscriptAccumulator.new()

    s = TranscriptAccumulator.ingest(s, "there is a moon", true)
    s = TranscriptAccumulator.ingest(s, "there is a moon", true)

    assert TranscriptAccumulator.stable_text(s) == "there is a moon"
  end
end
