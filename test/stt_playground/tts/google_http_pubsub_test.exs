defmodule SttPlayground.TTS.GoogleHttpPubSubTest do
  use ExUnit.Case, async: false

  alias SttPlayground.EventBus
  alias SttPlayground.TTS.GoogleHttp

  test "speak_text can deliver events via PubSub (deliver: :pubsub)" do
    # 2 samples -> 2 chunks when audio_chunk_samples=1
    pcm16 = <<0::signed-little-16, 42::signed-little-16>>
    audio_b64 = Base.encode64(pcm16)

    http_post = fn _finch_name, _url, _headers, _body ->
      {:ok, 200, Jason.encode!(%{"audioContent" => audio_b64})}
    end

    token_fetcher = fn _source, _scope -> {:ok, "TOKEN"} end

    start_supervised!({
      GoogleHttp,
      [
        http_post: http_post,
        token_fetcher: token_fetcher,
        audio_chunk_samples: 1,
        sample_rate_hz: 24_000
      ]
    })

    session_id = "tts-pubsub-1"

    Phoenix.PubSub.subscribe(SttPlayground.PubSub, EventBus.tts_topic(session_id))

    assert :ok = GoogleHttp.start_session(session_id, self(), deliver: :pubsub)

    assert_receive {:tts_event, %{"event" => "session_started", "session_id" => ^session_id}}, 200

    :ok = GoogleHttp.speak_text(session_id, "hello")

    assert_receive {:tts_event,
                    %{"event" => "audio_chunk", "session_id" => ^session_id, "seq" => 0}},
                   1_000

    assert_receive {:tts_event,
                    %{"event" => "audio_chunk", "session_id" => ^session_id, "seq" => 1}},
                   1_000

    assert_receive {:tts_event, %{"event" => "session_done", "session_id" => ^session_id}}, 1_000
  end
end
