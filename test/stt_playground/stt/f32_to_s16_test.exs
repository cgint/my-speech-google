defmodule SttPlayground.STT.F32ToS16Test do
  use ExUnit.Case, async: true

  alias SttPlayground.STT.GoogleGrpc.Session

  defmodule FakeTranscriptionServer do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def process_audio(pid, audio_data), do: GenServer.cast(pid, {:process_audio, audio_data})
    def end_stream(pid), do: GenServer.cast(pid, :end_stream)

    @impl true
    def init(opts) do
      {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid)}}
    end

    @impl true
    def handle_cast({:process_audio, audio_data}, state) do
      send(state.test_pid, {:fake_ts, :process_audio, audio_data})
      {:noreply, state}
    end

    def handle_cast(:end_stream, state) do
      send(state.test_pid, {:fake_ts, :end_stream})
      {:noreply, state}
    end
  end

  test "Float32 PCM (native endian) is converted to LINEAR16 little-endian" do
    native =
      case System.endianness() do
        :little ->
          <<
            -1.0::float-little-32,
            -0.5::float-little-32,
            0.0::float-little-32,
            0.5::float-little-32,
            1.0::float-little-32,
            2.0::float-little-32
          >>

        :big ->
          <<
            -1.0::float-big-32,
            -0.5::float-big-32,
            0.0::float-big-32,
            0.5::float-big-32,
            1.0::float-big-32,
            2.0::float-big-32
          >>
      end

    expected =
      <<
        -32767::signed-little-16,
        -16383::signed-little-16,
        0::signed-little-16,
        16383::signed-little-16,
        32767::signed-little-16,
        32767::signed-little-16
      >>

    {:ok, pid} =
      Session.start_link(
        session_id: "s1",
        owner_pid: self(),
        recognizer: "projects/p/locations/eu/recognizers/_",
        transcription_server_module: FakeTranscriptionServer,
        transcription_server_opts: [test_pid: self()]
      )

    b64 = Base.encode64(native)
    Session.push_chunk(pid, b64)

    assert_receive {:fake_ts, :process_audio, ^expected}, 200
  end
end
