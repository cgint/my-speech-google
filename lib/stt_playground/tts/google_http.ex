defmodule SttPlayground.TTS.GoogleHttp do
  @moduledoc """
  Elixir-native TTS provider using Google Cloud Text-to-Speech (REST).

  Emits events to the session owner via:

      {:tts_event, %{"event" => ..., "session_id" => ...}}

  Audio output is streamed as base64-encoded `f32le` PCM chunks.
  """

  use GenServer
  require Logger

  @type session_id :: String.t()

  @default_api_url "https://texttospeech.googleapis.com/v1/text:synthesize"
  @default_scope "https://www.googleapis.com/auth/cloud-platform"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def start_session(session_id, owner_pid, _opts \\ []),
    do: GenServer.call(__MODULE__, {:start_session, session_id, owner_pid})

  def speak_text(session_id, text),
    do: GenServer.cast(__MODULE__, {:speak_text, session_id, text})

  def stop_session(session_id), do: GenServer.cast(__MODULE__, {:stop_session, session_id})

  @impl true
  def init(opts) do
    state = %{
      api_url: Keyword.get(opts, :api_url, @default_api_url),
      scope: Keyword.get(opts, :scope, @default_scope),
      token_source: Keyword.get(opts, :token_source, :auto),
      quota_project_id: Keyword.get(opts, :quota_project_id, quota_project_id_from_env_or_adc()),
      finch_name: Keyword.get(opts, :finch_name, SttPlayground.Finch),
      http_post: Keyword.get(opts, :http_post, &__MODULE__.finch_post/4),
      token_fetcher: Keyword.get(opts, :token_fetcher, &__MODULE__.fetch_token/2),
      voice_name:
        Keyword.get(opts, :voice_name, System.get_env("TTS_VOICE_NAME") || "en-US-Neural2-F"),
      language_code:
        Keyword.get(opts, :language_code, System.get_env("TTS_LANGUAGE_CODE") || "en-US"),
      sample_rate_hz: Keyword.get(opts, :sample_rate_hz, env_int("TTS_SAMPLE_RATE_HZ", 24_000)),
      audio_chunk_samples: Keyword.get(opts, :audio_chunk_samples, 2_048),
      sessions: %{},
      owner_refs: %{},
      session_refs: %{}
    }

    Logger.info("[tts-google-http] started")
    send(self(), :emit_ready)

    {:ok, state}
  end

  @impl true
  def handle_info(:emit_ready, state) do
    # no session owner; this is useful for debugging/telemetry parity with PythonPort
    Logger.info("[tts-google-http] ready")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.owner_refs, ref) do
      {nil, _owner_refs} ->
        {:noreply, state}

      {session_id, owner_refs} ->
        state =
          state
          |> Map.put(:owner_refs, owner_refs)
          |> cleanup_session(session_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:start_session, session_id, owner_pid}, _from, state) do
    ref = Process.monitor(owner_pid)

    state =
      state
      |> put_in([:sessions, session_id], owner_pid)
      |> put_in([:owner_refs, ref], session_id)
      |> put_in([:session_refs, session_id], ref)

    send(owner_pid, {:tts_event, %{"event" => "session_started", "session_id" => session_id}})

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:stop_session, session_id}, state) do
    {:noreply, cleanup_session(state, session_id)}
  end

  @impl true
  def handle_cast({:speak_text, session_id, text}, state) do
    case Map.fetch(state.sessions, session_id) do
      :error ->
        {:noreply, state}

      {:ok, owner_pid} ->
        cfg =
          Map.take(state, [
            :api_url,
            :scope,
            :token_source,
            :quota_project_id,
            :http_post,
            :token_fetcher,
            :finch_name,
            :voice_name,
            :language_code,
            :sample_rate_hz,
            :audio_chunk_samples
          ])

        text = String.trim(to_string(text))

        Task.start(fn ->
          speak_text_task(cfg, owner_pid, session_id, text)
        end)

        {:noreply, state}
    end
  end

  defp cleanup_session(state, session_id) do
    state =
      if ref = state.session_refs[session_id] do
        Process.demonitor(ref, [:flush])

        state
        |> update_in([:owner_refs], &Map.delete(&1, ref))
        |> update_in([:session_refs], &Map.delete(&1, session_id))
      else
        state
      end

    update_in(state.sessions, &Map.delete(&1, session_id))
  end

  defp speak_text_task(cfg, owner_pid, session_id, text) do
    if text == "" do
      send(owner_pid, {:tts_event, %{"event" => "session_done", "session_id" => session_id}})
      return(:ok)
    end

    with {:ok, token} <- cfg.token_fetcher.(cfg.token_source, cfg.scope),
         {:ok, pcm16, sample_rate} <- synthesize_pcm16(cfg, token, text),
         f32le <- pcm16le_to_f32le(pcm16) do
      f32le
      |> chunk_f32le(cfg.audio_chunk_samples)
      |> Enum.with_index()
      |> Enum.each(fn {chunk, seq} ->
        send(owner_pid, {
          :tts_event,
          %{
            "event" => "audio_chunk",
            "session_id" => session_id,
            "seq" => seq,
            "pcm_b64" => Base.encode64(chunk),
            "sample_rate" => sample_rate,
            "channels" => 1,
            "format" => "f32le"
          }
        })
      end)

      send(owner_pid, {:tts_event, %{"event" => "session_done", "session_id" => session_id}})
    else
      {:error, reason} ->
        send(owner_pid, {
          :tts_event,
          %{
            "event" => "error",
            "session_id" => session_id,
            "message" => "tts failed: #{inspect(reason)}"
          }
        })
    end
  end

  defp synthesize_pcm16(cfg, token, text) do
    body =
      Jason.encode!(%{
        input: %{text: text},
        voice: %{languageCode: cfg.language_code, name: cfg.voice_name},
        audioConfig: %{audioEncoding: "LINEAR16", sampleRateHertz: cfg.sample_rate_hz}
      })

    headers =
      [
        {"authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ]
      |> maybe_put_quota_project(cfg.quota_project_id)

    with {:ok, status, resp_body} <- cfg.http_post.(cfg.finch_name, cfg.api_url, headers, body),
         :ok <- ensure_200(status, resp_body),
         {:ok, decoded} <- Jason.decode(resp_body),
         {:ok, audio_b64} <- fetch_audio_content(decoded),
         {:ok, pcm16} <- Base.decode64(audio_b64) do
      {:ok, pcm16, cfg.sample_rate_hz}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  def finch_post(finch_name, url, headers, body) do
    req = Finch.build(:post, url, headers, body)

    case Finch.request(req, finch_name) do
      {:ok, %{status: status, body: resp_body}} -> {:ok, status, resp_body}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_token(:auto, scope), do: fetch_token(nil, scope)

  def fetch_token(nil, scope) do
    # Automatic credential discovery (ADC):
    # - env/config JSON
    # - GOOGLE_APPLICATION_CREDENTIALS(_JSON)
    # - gcloud application_default_credentials.json
    # - metadata service
    case Goth.Token.fetch(scopes: [scope]) do
      {:ok, %{token: token}} when is_binary(token) -> {:ok, token}
      {:ok, %Goth.Token{token: token}} when is_binary(token) -> {:ok, token}
      other -> {:error, other}
    end
  end

  def fetch_token(source, scope) do
    case Goth.Token.fetch(source: source, scopes: [scope]) do
      {:ok, %{token: token}} when is_binary(token) -> {:ok, token}
      {:ok, %Goth.Token{token: token}} when is_binary(token) -> {:ok, token}
      other -> {:error, other}
    end
  end

  defp quota_project_id_from_env_or_adc do
    env = System.get_env("GOOGLE_CLOUD_QUOTA_PROJECT")

    cond do
      is_binary(env) and String.trim(env) != "" ->
        String.trim(env)

      true ->
        adc_quota_project_id()
    end
  end

  defp adc_quota_project_id do
    path =
      System.get_env("GOOGLE_APPLICATION_CREDENTIALS") ||
        Path.expand("~/.config/gcloud/application_default_credentials.json")

    with {:ok, bin} <- File.read(path),
         {:ok, json} <- Jason.decode(bin),
         quota when is_binary(quota) <- Map.get(json, "quota_project_id"),
         quota = String.trim(quota),
         false <- quota == "" do
      quota
    else
      _ -> nil
    end
  end

  defp maybe_put_quota_project(headers, quota_project_id)

  defp maybe_put_quota_project(headers, quota_project_id)
       when is_binary(quota_project_id) and quota_project_id != "" do
    [{"x-goog-user-project", quota_project_id} | headers]
  end

  defp maybe_put_quota_project(headers, _), do: headers

  defp fetch_audio_content(%{"audioContent" => audio}) when is_binary(audio), do: {:ok, audio}
  defp fetch_audio_content(map), do: {:error, {:missing_audio_content, map}}

  defp ensure_200(200, _body), do: :ok
  defp ensure_200(status, body), do: {:error, {:http_status, status, body}}

  defp pcm16le_to_f32le(pcm16) when is_binary(pcm16) do
    for <<sample::signed-little-16 <- pcm16>>, into: <<>> do
      <<sample / 32768.0::float-little-32>>
    end
  end

  defp chunk_f32le(f32le, samples_per_chunk) do
    bytes_per_chunk = samples_per_chunk * 4

    do_chunk(f32le, bytes_per_chunk, [])
    |> Enum.reverse()
  end

  defp do_chunk(<<>>, _bytes_per_chunk, acc), do: acc

  defp do_chunk(bin, bytes_per_chunk, acc) do
    case bin do
      <<chunk::binary-size(bytes_per_chunk), rest::binary>> ->
        do_chunk(rest, bytes_per_chunk, [chunk | acc])

      _ ->
        [bin | acc]
    end
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil ->
        default

      "" ->
        default

      v ->
        case Integer.parse(v) do
          {i, _} -> i
          :error -> default
        end
    end
  end

  defp return(value), do: value
end
