defmodule SttPlayground.TTS.PythonPortTest do
  use ExUnit.Case, async: false

  alias SttPlayground.TTS.PythonPort

  @worker_path Path.expand("../../support/tts_fake_worker.py", __DIR__)

  setup do
    handler_id = "tts-python-port-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:stt_playground, :tts, :worker, :started],
        [:stt_playground, :tts, :worker, :ready],
        [:stt_playground, :tts, :worker, :exit],
        [:stt_playground, :tts, :worker, :invalid_payload]
      ],
      fn event, measurements, metadata, test_pid ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      self()
    )

    start_supervised!({
      PythonPort,
      [
        worker_path: @worker_path,
        runner: :python
      ]
    })

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  test "emits ready telemetry and can speak a chunk" do
    assert_receive {:telemetry, [:stt_playground, :tts, :worker, :started], _m, _meta}, 1_000
    assert_receive {:telemetry, [:stt_playground, :tts, :worker, :ready], _m, _meta}, 1_000

    session_id = "t1"
    assert :ok = PythonPort.start_session(session_id, self())

    PythonPort.speak_text(session_id, "hello")

    assert_receive {:tts_event, %{"event" => "audio_chunk", "session_id" => ^session_id}}, 1_000
    assert_receive {:tts_event, %{"event" => "session_done", "session_id" => ^session_id}}, 1_000

    PythonPort.stop_session(session_id)
  end
end
