defmodule SttPlayground.ProvidersFacadeTest do
  use ExUnit.Case, async: true

  defmodule FakeSTT do
    def start_session(session_id, owner_pid, _opts) do
      send(owner_pid, {:fake_stt, :start_session, session_id})
      :ok
    end

    def push_chunk(session_id, pcm_b64) do
      send(self(), {:fake_stt, :push_chunk, session_id, pcm_b64})
      :ok
    end

    def stop_session(session_id) do
      send(self(), {:fake_stt, :stop_session, session_id})
      :ok
    end
  end

  defmodule FakeTTS do
    def start_session(session_id, owner_pid, _opts) do
      send(owner_pid, {:fake_tts, :start_session, session_id})
      :ok
    end

    def speak_text(session_id, text) do
      send(self(), {:fake_tts, :speak_text, session_id, text})
      :ok
    end

    def stop_session(session_id) do
      send(self(), {:fake_tts, :stop_session, session_id})
      :ok
    end
  end

  setup do
    old_stt = Application.get_env(:stt_playground, :stt_provider)
    old_tts = Application.get_env(:stt_playground, :tts_provider)

    Application.put_env(:stt_playground, :stt_provider, FakeSTT)
    Application.put_env(:stt_playground, :tts_provider, FakeTTS)

    on_exit(fn ->
      Application.put_env(:stt_playground, :stt_provider, old_stt)
      Application.put_env(:stt_playground, :tts_provider, old_tts)
    end)

    :ok
  end

  test "STT facade delegates to configured provider" do
    assert :ok = SttPlayground.STT.start_session("s1", self(), [])
    assert_receive {:fake_stt, :start_session, "s1"}

    assert :ok = SttPlayground.STT.push_chunk("s1", "pcm")
    assert_receive {:fake_stt, :push_chunk, "s1", "pcm"}

    assert :ok = SttPlayground.STT.stop_session("s1")
    assert_receive {:fake_stt, :stop_session, "s1"}
  end

  test "TTS facade delegates to configured provider" do
    assert :ok = SttPlayground.TTS.start_session("t1", self(), [])
    assert_receive {:fake_tts, :start_session, "t1"}

    assert :ok = SttPlayground.TTS.speak_text("t1", "hello")
    assert_receive {:fake_tts, :speak_text, "t1", "hello"}

    assert :ok = SttPlayground.TTS.stop_session("t1")
    assert_receive {:fake_tts, :stop_session, "t1"}
  end
end
