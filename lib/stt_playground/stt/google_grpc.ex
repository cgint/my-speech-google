defmodule SttPlayground.STT.GoogleGrpc do
  @moduledoc """
  Elixir-native STT provider using Google Cloud Speech-to-Text v2 streaming via gRPC.

  This provider is a thin wrapper around `ExGoogleSTT.TranscriptionServer`.

  Events are delivered to the session owner as:

      {:stt_event, %{"event" => "partial" | "final" | "error", ...}}

  Input audio is expected to be base64-encoded raw Float32 PCM bytes at 16kHz mono
  (f32 bytes in the server's native endianness), matching the browser AudioWorklet.

  We convert that stream to LINEAR16 (s16le) before sending to Google.
  """

  use GenServer
  require Logger

  @default_scope "https://www.googleapis.com/auth/cloud-platform"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def start_session(session_id, owner_pid, opts \\ []),
    do: GenServer.call(__MODULE__, {:start_session, session_id, owner_pid, opts})

  def push_chunk(session_id, pcm_b64),
    do: GenServer.cast(__MODULE__, {:push_chunk, session_id, pcm_b64})

  def stop_session(session_id), do: GenServer.cast(__MODULE__, {:stop_session, session_id})

  @impl true
  def init(opts) do
    state = %{
      recognizer:
        Keyword.get(opts, :recognizer, recognizer_from_env() || recognizer_from_config()),
      language_codes: Keyword.get(opts, :language_codes, language_codes_from_env()),
      model: Keyword.get(opts, :model, System.get_env("STT_MODEL") || "chirp_3"),
      interim_results: Keyword.get(opts, :interim_results, true),
      finalize_after_ms: Keyword.get(opts, :finalize_after_ms, 600),
      token_scope: Keyword.get(opts, :token_scope, @default_scope),
      sessions: %{},
      owner_refs: %{},
      session_refs: %{}
    }

    if is_nil(state.recognizer) or state.recognizer == "" do
      Logger.warning(
        "[stt-google-grpc] recognizer not configured. Set STT_RECOGNIZER or config :ex_google_stt, :recognizer"
      )
    end

    Logger.info("[stt-google-grpc] started")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_session, session_id, owner_pid, opts}, _from, state) do
    ref = Process.monitor(owner_pid)

    session_opts =
      [
        session_id: session_id,
        owner_pid: owner_pid,
        deliver: Keyword.get(opts, :deliver, :direct),
        recognizer: state.recognizer,
        language_codes: state.language_codes,
        model: state.model,
        interim_results: state.interim_results,
        finalize_after_ms: state.finalize_after_ms
      ]
      |> Keyword.merge(opts)

    case __MODULE__.Session.start_link(session_opts) do
      {:ok, pid} ->
        state =
          state
          |> put_in([:sessions, session_id], pid)
          |> put_in([:owner_refs, ref], session_id)
          |> put_in([:session_refs, session_id], ref)

        {:reply, :ok, state}

      {:error, reason} ->
        Process.demonitor(ref, [:flush])
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:push_chunk, session_id, pcm_b64}, state) do
    case Map.fetch(state.sessions, session_id) do
      :error ->
        {:noreply, state}

      {:ok, pid} ->
        __MODULE__.Session.push_chunk(pid, pcm_b64)
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:stop_session, session_id}, state) do
    if pid = state.sessions[session_id] do
      __MODULE__.Session.stop(pid)
    end

    {:noreply, cleanup_session(state, session_id)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.owner_refs, ref) do
      {nil, _owner_refs} ->
        {:noreply, state}

      {session_id, owner_refs} ->
        if pid = state.sessions[session_id] do
          __MODULE__.Session.stop(pid)
        end

        state =
          state
          |> Map.put(:owner_refs, owner_refs)
          |> cleanup_session(session_id)

        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

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

  defp recognizer_from_config do
    Application.get_env(:ex_google_stt, :recognizer)
  end

  defp recognizer_from_env do
    project = System.get_env("GOOGLE_CLOUD_PROJECT") || System.get_env("VERTEXAI_PROJECT")
    location = System.get_env("STT_LOCATION") || "eu"
    recognizer_id = System.get_env("STT_RECOGNIZER_ID") || "_"

    stt_recognizer = System.get_env("STT_RECOGNIZER")

    cond do
      is_binary(stt_recognizer) and stt_recognizer != "" ->
        stt_recognizer

      is_binary(project) and project != "" ->
        "projects/#{project}/locations/#{location}/recognizers/#{recognizer_id}"

      true ->
        nil
    end
  end

  defp language_codes_from_env do
    langs = System.get_env("STT_LANGUAGE_CODES") || "en-US"

    langs
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> ["en-US"]
      list -> list
    end
  end

  defmodule Session do
    @moduledoc false

    use GenServer

    require Logger

    alias ExGoogleSTT.{Error, SpeechEvent, Transcript, TranscriptionServer}

    alias Google.Cloud.Speech.V2.ExplicitDecodingConfig

    defp endpoint_from_location("global"), do: nil

    defp endpoint_from_location(location) when is_binary(location) do
      location = String.trim(location)

      cond do
        location == "" -> nil
        location == "global" -> nil
        true -> "#{location}-speech.googleapis.com"
      end
    end

    defp endpoint_from_location(_), do: nil

    defp location_from_recognizer(recognizer) when is_binary(recognizer) do
      case Regex.run(~r{/locations/([^/]+)/recognizers/}, recognizer) do
        [_, location] -> location
        _ -> nil
      end
    end

    defp location_from_recognizer(_), do: nil

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    def push_chunk(pid, pcm_b64), do: GenServer.cast(pid, {:push_chunk, pcm_b64})
    def stop(pid), do: GenServer.cast(pid, :stop)

    @impl true
    def init(opts) do
      session_id = Keyword.fetch!(opts, :session_id)
      owner_pid = Keyword.fetch!(opts, :owner_pid)

      deliver = Keyword.get(opts, :deliver, :direct)

      recognizer = Keyword.get(opts, :recognizer)
      language_codes = Keyword.get(opts, :language_codes, ["en-US"])
      model = Keyword.get(opts, :model, "latest_long")
      interim_results = Keyword.get(opts, :interim_results, true)
      finalize_after_ms = Keyword.get(opts, :finalize_after_ms, 600)

      decoding =
        %ExplicitDecodingConfig{
          encoding: :LINEAR16,
          sample_rate_hertz: 16_000,
          audio_channel_count: 1
        }

      endpoint =
        Keyword.get(opts, :endpoint) ||
          case location_from_recognizer(recognizer) do
            "global" ->
              nil

            nil ->
              endpoint_from_location(System.get_env("STT_LOCATION") || "eu")

            location ->
              endpoint_from_location(location)
          end

      ts_opts =
        [
          target: self(),
          recognizer: recognizer,
          language_codes: language_codes,
          model: model,
          interim_results: interim_results,
          explicit_decoding_config: decoding,
          endpoint: endpoint
        ]
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      ts_mod = Keyword.get(opts, :transcription_server_module, TranscriptionServer)
      extra_ts_opts = Keyword.get(opts, :transcription_server_opts, [])

      {:ok, ts_pid} = ts_mod.start_link(ts_opts ++ extra_ts_opts)

      trace? = Keyword.get(opts, :trace, env_bool("STT_TRACE", false))

      state = %{
        session_id: session_id,
        owner_pid: owner_pid,
        deliver: deliver,
        ts_mod: ts_mod,
        ts_pid: ts_pid,
        trace?: trace?,
        chunk_count: 0,
        stop_requested: false,
        finalize_after_ms: finalize_after_ms,
        finalize_timer: nil,
        final_segments: [],
        last_interim: ""
      }

      {:ok, state}
    end

    @impl true
    def handle_cast({:push_chunk, pcm_b64}, state) do
      with {:ok, f32_bin} <- Base.decode64(pcm_b64),
           {:ok, s16le} <- f32_native_16k_mono_to_s16le(f32_bin) do
        _ = state.ts_mod.process_audio(state.ts_pid, s16le)
      else
        :error ->
          deliver(state, %{
            "event" => "error",
            "session_id" => state.session_id,
            "message" => "invalid base64 audio"
          })

        {:error, reason} ->
          deliver(state, %{
            "event" => "error",
            "session_id" => state.session_id,
            "message" => "audio conversion failed: #{inspect(reason)}"
          })
      end

      {:noreply, %{state | chunk_count: state.chunk_count + 1}}
    end

    @impl true
    def handle_cast(:stop, state) do
      _ = state.ts_mod.end_stream(state.ts_pid)

      state = %{state | stop_requested: true}
      {:noreply, schedule_finalize(state)}
    end

    @impl true
    def handle_info({:stt_event, %Transcript{} = transcript}, state) do
      content = (transcript.content || "") |> String.trim()

      if state.trace? and content != "" do
        Logger.info(
          "[stt-trace][#{state.session_id}] is_final=#{inspect(transcript.is_final)} content=#{inspect(content)}"
        )
      end

      state =
        cond do
          content == "" ->
            state

          transcript.is_final ->
            %{state | final_segments: state.final_segments ++ [content], last_interim: ""}

          true ->
            %{state | last_interim: content}
        end

      final_text = state.final_segments |> Enum.join(" ") |> String.trim()
      combined = combine_text(state.final_segments, state.last_interim)

      if combined != "" do
        deliver(state, %{
          "event" => "partial",
          "session_id" => state.session_id,
          "text" => combined,
          "final_text" => final_text,
          "interim_text" => state.last_interim,
          "chunk_count" => state.chunk_count
        })
      end

      state = if state.stop_requested, do: schedule_finalize(state), else: state
      {:noreply, state}
    end

    def handle_info({:stt_event, %SpeechEvent{}}, state), do: {:noreply, state}
    def handle_info({:stt_event, :stream_timeout}, state), do: {:noreply, state}

    def handle_info({:stt_event, %Error{} = err}, state) do
      deliver(state, %{
        "event" => "error",
        "session_id" => state.session_id,
        "message" => "stt failed: #{err.message}"
      })

      {:stop, :normal, state}
    end

    def handle_info(:finalize, state) do
      final_text = combine_text(state.final_segments, state.last_interim)

      deliver(state, %{
        "event" => "final",
        "session_id" => state.session_id,
        "text" => final_text
      })

      {:stop, :normal, state}
    end

    def handle_info(_msg, state), do: {:noreply, state}

    defp deliver(%{deliver: :pubsub, session_id: session_id}, payload) when is_map(payload) do
      SttPlayground.EventBus.broadcast_stt(session_id, payload)
    end

    defp deliver(%{deliver: :direct, owner_pid: owner_pid}, payload)
         when is_pid(owner_pid) and is_map(payload) do
      send(owner_pid, {:stt_event, payload})
      :ok
    end

    defp deliver(%{deliver: :both, session_id: session_id, owner_pid: owner_pid}, payload)
         when is_pid(owner_pid) and is_map(payload) do
      SttPlayground.EventBus.broadcast_stt(session_id, payload)
      send(owner_pid, {:stt_event, payload})
      :ok
    end

    defp deliver(_state, _payload), do: :ok

    defp schedule_finalize(state) do
      if state.finalize_timer, do: Process.cancel_timer(state.finalize_timer)
      ref = Process.send_after(self(), :finalize, state.finalize_after_ms)
      %{state | finalize_timer: ref}
    end

    defp combine_text(final_segments, last_interim) do
      (final_segments ++ if(last_interim != "", do: [last_interim], else: []))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")
      |> String.trim()
    end

    # The browser sends float32 samples in the server's native endianness.
    # Convert to LINEAR16 little-endian as required by Google STT.
    defp f32_native_16k_mono_to_s16le(pcm_f32_native) when is_binary(pcm_f32_native) do
      endianness = System.endianness()

      case endianness do
        :little -> {:ok, f32_to_s16le(pcm_f32_native, :little)}
        :big -> {:ok, f32_to_s16le(pcm_f32_native, :big)}
        other -> {:error, {:unknown_endianness, other}}
      end
    end

    defp f32_to_s16le(bin, :little), do: do_f32_to_s16le(bin, <<>>, :little)
    defp f32_to_s16le(bin, :big), do: do_f32_to_s16le(bin, <<>>, :big)

    defp do_f32_to_s16le(<<>>, acc, _endian), do: acc

    defp do_f32_to_s16le(bin, acc, :little) do
      case bin do
        <<sample::float-little-32, rest::binary>> ->
          do_f32_to_s16le(rest, <<acc::binary, float_to_i16(sample)::signed-little-16>>, :little)

        _ ->
          # ignore trailing bytes
          acc
      end
    end

    defp do_f32_to_s16le(bin, acc, :big) do
      case bin do
        <<sample::float-big-32, rest::binary>> ->
          do_f32_to_s16le(rest, <<acc::binary, float_to_i16(sample)::signed-little-16>>, :big)

        _ ->
          acc
      end
    end

    defp env_bool(name, default) do
      case System.get_env(name) do
        nil ->
          default

        "" ->
          default

        "1" ->
          true

        "true" ->
          true

        "TRUE" ->
          true

        "yes" ->
          true

        "YES" ->
          true

        "0" ->
          false

        "false" ->
          false

        "FALSE" ->
          false

        "no" ->
          false

        "NO" ->
          false

        other ->
          Logger.warning("[stt-google-grpc] invalid boolean env #{name}=#{inspect(other)}")
          default
      end
    end

    defp float_to_i16(f) when is_float(f) do
      f =
        cond do
          f > 1.0 -> 1.0
          f < -1.0 -> -1.0
          true -> f
        end

      trunc(f * 32767.0)
    end
  end
end
