defmodule SttPlayground.EventBusTest do
  use ExUnit.Case, async: true

  alias SttPlayground.EventBus

  test "stt_topic/1 and tts_topic/1" do
    assert EventBus.stt_topic("123") == "stt:123"
    assert EventBus.tts_topic("123") == "tts:123"
  end

  test "broadcast_stt delivers to subscribers" do
    session_id = "s-bus"
    :ok = EventBus.subscribe_stt(session_id)

    EventBus.broadcast_stt(session_id, %{"event" => "partial", "session_id" => session_id})

    assert_receive {:stt_event, %{"event" => "partial", "session_id" => ^session_id}}, 200
  end
end
