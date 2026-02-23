defmodule SttPlayground.TTS.Provider do
  @moduledoc """
  Provider contract for text-to-speech (TTS).

  This defines the stable interface the rest of the application should call.
  Implementations may be backed by external workers (ports) or Elixir-native clients.

  The provider is expected to deliver events to the session owner as:

      {:tts_event, map}

  where the map contains at least:

  - "event" ("audio_chunk" | "session_done" | "error" | ...)
  - "session_id"

  """

  @type session_id :: String.t()

  @callback start_session(session_id(), pid(), keyword()) :: :ok | {:error, term()}
  @callback speak_text(session_id(), String.t()) :: :ok
  @callback stop_session(session_id()) :: :ok
end
