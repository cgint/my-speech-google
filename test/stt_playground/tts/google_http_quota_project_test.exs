defmodule SttPlayground.TTS.GoogleHttpQuotaProjectTest do
  use ExUnit.Case, async: false

  alias SttPlayground.TTS.GoogleHttp

  setup do
    # Ensure the module under test reads from env deterministically.
    old_quota = System.get_env("GOOGLE_CLOUD_QUOTA_PROJECT")
    old_creds = System.get_env("GOOGLE_APPLICATION_CREDENTIALS")

    on_exit(fn ->
      set_or_unset_env("GOOGLE_CLOUD_QUOTA_PROJECT", old_quota)
      set_or_unset_env("GOOGLE_APPLICATION_CREDENTIALS", old_creds)
    end)

    :ok
  end

  test "adds x-goog-user-project header from GOOGLE_CLOUD_QUOTA_PROJECT" do
    System.put_env("GOOGLE_CLOUD_QUOTA_PROJECT", "qp-env")

    audio_b64 = Base.encode64(<<0::signed-little-16>>)

    http_post = fn _finch_name, _url, headers, _body ->
      assert {"x-goog-user-project", "qp-env"} in headers
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

    session_id = "qp1"

    assert :ok = GoogleHttp.start_session(session_id, self())
    :ok = GoogleHttp.speak_text(session_id, "hello")

    assert_receive {:tts_event, %{"event" => "session_done", "session_id" => ^session_id}}, 1_000
  end

  test "adds x-goog-user-project header from quota_project_id in ADC json" do
    System.delete_env("GOOGLE_CLOUD_QUOTA_PROJECT")

    tmp = Path.join(System.tmp_dir!(), "adc-#{System.unique_integer([:positive])}.json")

    File.write!(tmp, Jason.encode!(%{"quota_project_id" => "qp-adc"}))
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS", tmp)

    audio_b64 = Base.encode64(<<0::signed-little-16>>)

    http_post = fn _finch_name, _url, headers, _body ->
      assert {"x-goog-user-project", "qp-adc"} in headers
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

    session_id = "qp2"

    assert :ok = GoogleHttp.start_session(session_id, self())
    :ok = GoogleHttp.speak_text(session_id, "hello")

    assert_receive {:tts_event, %{"event" => "session_done", "session_id" => ^session_id}}, 1_000
  end

  defp set_or_unset_env(_name, nil), do: :ok
  defp set_or_unset_env(name, value), do: System.put_env(name, value)
end
