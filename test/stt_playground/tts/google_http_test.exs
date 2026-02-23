defmodule SttPlayground.TTS.GoogleHttpTest do
  use ExUnit.Case, async: false

  alias SttPlayground.TTS.GoogleHttp

  test "speak_text emits audio_chunk events and session_done" do
    # 6 samples -> 3 chunks when audio_chunk_samples=2
    pcm16 =
      <<
        0::signed-little-16,
        32767::signed-little-16,
        -32768::signed-little-16,
        1000::signed-little-16,
        -1000::signed-little-16,
        42::signed-little-16
      >>

    audio_b64 = Base.encode64(pcm16)

    http_post = fn _finch_name, _url, headers, _body ->
      assert {"authorization", "Bearer TOKEN"} in headers

      {:ok, 200, Jason.encode!(%{"audioContent" => audio_b64})}
    end

    token_fetcher = fn _source, _scope -> {:ok, "TOKEN"} end

    start_supervised!({
      GoogleHttp,
      [
        http_post: http_post,
        token_fetcher: token_fetcher,
        audio_chunk_samples: 2,
        sample_rate_hz: 24_000
      ]
    })

    session_id = "t1"

    assert :ok = GoogleHttp.start_session(session_id, self())
    assert_receive {:tts_event, %{"event" => "session_started", "session_id" => ^session_id}}

    :ok = GoogleHttp.speak_text(session_id, "hello")

    assert_receive {:tts_event,
                    %{
                      "event" => "audio_chunk",
                      "session_id" => ^session_id,
                      "seq" => 0,
                      "pcm_b64" => _
                    }},
                   1_000

    assert_receive {:tts_event,
                    %{
                      "event" => "audio_chunk",
                      "session_id" => ^session_id,
                      "seq" => 1,
                      "pcm_b64" => _
                    }},
                   1_000

    assert_receive {:tts_event,
                    %{
                      "event" => "audio_chunk",
                      "session_id" => ^session_id,
                      "seq" => 2,
                      "pcm_b64" => _
                    }},
                   1_000

    assert_receive {:tts_event, %{"event" => "session_done", "session_id" => ^session_id}}, 1_000
  end
end
