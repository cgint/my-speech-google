defmodule SttPlayground.EventBus do
  @moduledoc """
  Centralized PubSub interface for STT/TTS session events.

  This wraps `Phoenix.PubSub` so topic naming and message shapes are consistent
  across providers and consumers.

  Topic naming follows the `resource:<id>` convention:

    - STT: `stt:<session_id>`
    - TTS: `tts:<session_id>`

  Messages are broadcast as plain process messages:

    - STT: `{:stt_event, payload_map}`
    - TTS: `{:tts_event, payload_map}`
  """

  @pubsub SttPlayground.PubSub

  @spec stt_topic(String.t()) :: String.t()
  def stt_topic(session_id) when is_binary(session_id), do: "stt:#{session_id}"

  @spec tts_topic(String.t()) :: String.t()
  def tts_topic(session_id) when is_binary(session_id), do: "tts:#{session_id}"

  @spec subscribe_stt(String.t()) :: :ok | {:error, term()}
  def subscribe_stt(session_id), do: Phoenix.PubSub.subscribe(@pubsub, stt_topic(session_id))

  @spec unsubscribe_stt(String.t()) :: :ok | {:error, term()}
  def unsubscribe_stt(session_id), do: Phoenix.PubSub.unsubscribe(@pubsub, stt_topic(session_id))

  @spec broadcast_stt(String.t(), map()) :: :ok
  def broadcast_stt(session_id, payload) when is_map(payload) do
    Phoenix.PubSub.broadcast(@pubsub, stt_topic(session_id), {:stt_event, payload})
  end

  @spec subscribe_tts(String.t()) :: :ok | {:error, term()}
  def subscribe_tts(session_id), do: Phoenix.PubSub.subscribe(@pubsub, tts_topic(session_id))

  @spec unsubscribe_tts(String.t()) :: :ok | {:error, term()}
  def unsubscribe_tts(session_id), do: Phoenix.PubSub.unsubscribe(@pubsub, tts_topic(session_id))

  @spec broadcast_tts(String.t(), map()) :: :ok
  def broadcast_tts(session_id, payload) when is_map(payload) do
    Phoenix.PubSub.broadcast(@pubsub, tts_topic(session_id), {:tts_event, payload})
  end
end
