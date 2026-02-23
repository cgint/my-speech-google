defmodule SttPlayground.STT do
  @moduledoc """
  STT facade.

  Callers should use this module instead of directly depending on a concrete STT backend.
  The backend is selected via application config `:stt_provider`.
  """

  @spec provider_module() :: module()
  def provider_module do
    Application.get_env(:stt_playground, :stt_provider, SttPlayground.STT.PythonPort)
  end

  @spec start_session(String.t(), pid(), keyword()) :: :ok | {:error, term()}
  def start_session(session_id, owner_pid, opts \\ []) do
    provider = provider_module()

    try do
      cond do
        function_exported?(provider, :start_session, 3) ->
          apply(provider, :start_session, [session_id, owner_pid, opts])

        function_exported?(provider, :start_session, 2) ->
          apply(provider, :start_session, [session_id, owner_pid])

        true ->
          {:error, {:provider_missing_callback, {provider, :start_session}}}
      end
    catch
      :exit, {:noproc, _} -> {:error, :provider_not_running}
      :exit, reason -> {:error, {:provider_exit, reason}}
    end
  end

  @spec push_chunk(String.t(), String.t()) :: :ok | {:error, term()}
  def push_chunk(session_id, pcm_b64) do
    provider = provider_module()

    try do
      cond do
        function_exported?(provider, :push_chunk, 2) ->
          apply(provider, :push_chunk, [session_id, pcm_b64])

        function_exported?(provider, :audio_chunk, 2) ->
          apply(provider, :audio_chunk, [session_id, pcm_b64])

        true ->
          {:error, {:provider_missing_callback, {provider, :push_chunk}}}
      end
    catch
      :exit, {:noproc, _} -> {:error, :provider_not_running}
      :exit, reason -> {:error, {:provider_exit, reason}}
    end
  end

  @spec audio_chunk(String.t(), String.t()) :: :ok | {:error, term()}
  def audio_chunk(session_id, pcm_b64), do: push_chunk(session_id, pcm_b64)

  @spec stop_session(String.t()) :: :ok | {:error, term()}
  def stop_session(session_id) do
    provider = provider_module()

    try do
      apply(provider, :stop_session, [session_id])
    catch
      :exit, {:noproc, _} -> {:error, :provider_not_running}
      :exit, reason -> {:error, {:provider_exit, reason}}
    end
  end

  @spec provider_running?() :: boolean()
  def provider_running? do
    Process.whereis(provider_module()) != nil
  end

  @spec ensure_provider_loaded!() :: module()
  def ensure_provider_loaded! do
    provider = provider_module()

    unless Code.ensure_loaded?(provider) do
      raise "STT provider module not available: #{inspect(provider)}"
    end

    provider
  end
end
