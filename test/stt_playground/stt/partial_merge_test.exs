defmodule SttPlayground.STT.PartialMergeTest do
  use ExUnit.Case, async: true

  alias SttPlayground.STT.PartialMerge

  test "merges sliding-window partials by word overlap" do
    t0 = ""
    t1 = PartialMerge.merge(t0, "hello there")
    assert t1 == "hello there"

    t2 = PartialMerge.merge(t1, "there what is")
    assert t2 == "hello there what is"

    t3 = PartialMerge.merge(t2, "what is going on")
    assert t3 == "hello there what is going on"
  end

  test "incoming that already includes prev wins" do
    assert PartialMerge.merge("hello", "hello there") == "hello there"
  end

  test "empty incoming keeps previous" do
    assert PartialMerge.merge("hello there", "") == "hello there"
    assert PartialMerge.merge("hello there", "   ") == "hello there"
  end
end
