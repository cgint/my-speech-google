defmodule SttPlayground.STT.GoogleGrpcTest do
  use ExUnit.Case, async: true

  alias SttPlayground.STT.GoogleGrpc.Session

  defmodule FakeTranscriptionServer do
    use GenServer

    def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})
    def process_audio(_pid, _audio), do: :ok
    def end_stream(_pid), do: :ok

    @impl true
    def init(state), do: {:ok, state}
  end

  test "Session forwards partial and final events based on Transcript messages" do
    {:ok, pid} =
      Session.start_link(
        session_id: "s1",
        owner_pid: self(),
        recognizer: "projects/p/locations/eu/recognizers/_",
        finalize_after_ms: 20,
        transcription_server_module: FakeTranscriptionServer
      )

    # Simulate interim
    send(pid, {:stt_event, %ExGoogleSTT.Transcript{content: "hello", is_final: false}})

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s1",
                      "text" => "hello",
                      "final_text" => "",
                      "interim_text" => "hello"
                    }},
                   200

    # Simulate final segment
    send(pid, {:stt_event, %ExGoogleSTT.Transcript{content: "world", is_final: true}})

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s1",
                      "text" => "world",
                      "final_text" => "world",
                      "interim_text" => ""
                    }},
                   200

    # Stop triggers finalize timer; final should join segments
    Session.stop(pid)

    assert_receive {:stt_event,
                    %{
                      "event" => "final",
                      "session_id" => "s1",
                      "text" => "world"
                    }},
                   500
  end

  test "Session keeps final_text monotonic across volatile interim updates" do
    {:ok, pid} =
      Session.start_link(
        session_id: "s2",
        owner_pid: self(),
        recognizer: "projects/p/locations/eu/recognizers/_",
        finalize_after_ms: 20,
        transcription_server_module: FakeTranscriptionServer
      )

    send(pid, {:stt_event, %ExGoogleSTT.Transcript{content: "okay", is_final: false}})

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s2",
                      "final_text" => "",
                      "interim_text" => "okay"
                    }},
                   200

    send(
      pid,
      {:stt_event, %ExGoogleSTT.Transcript{content: "okay so this is the Moon", is_final: true}}
    )

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s2",
                      "final_text" => "okay so this is the Moon",
                      "interim_text" => ""
                    }},
                   200

    # Volatile interims should not change final_text
    send(pid, {:stt_event, %ExGoogleSTT.Transcript{content: "and", is_final: false}})

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s2",
                      "final_text" => "okay so this is the Moon",
                      "interim_text" => "and"
                    }},
                   200

    send(pid, {:stt_event, %ExGoogleSTT.Transcript{content: "and this is", is_final: false}})

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s2",
                      "final_text" => "okay so this is the Moon",
                      "interim_text" => "and this is"
                    }},
                   200

    send(
      pid,
      {:stt_event, %ExGoogleSTT.Transcript{content: "and this is the Sun", is_final: true}}
    )

    assert_receive {:stt_event,
                    %{
                      "event" => "partial",
                      "session_id" => "s2",
                      "final_text" => "okay so this is the Moon and this is the Sun",
                      "interim_text" => ""
                    }},
                   200

    Session.stop(pid)

    assert_receive {:stt_event,
                    %{
                      "event" => "final",
                      "session_id" => "s2",
                      "text" => "okay so this is the Moon and this is the Sun"
                    }},
                   500
  end
end
