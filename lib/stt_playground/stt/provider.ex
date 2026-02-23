defmodule SttPlayground.STT.Provider do
  @moduledoc """
  Provider contract for speech-to-text (STT).

  This defines the stable interface the rest of the application should call.
  Implementations may be backed by external workers (ports) or Elixir-native clients.

  The provider is expected to deliver events to the session owner as:

      {:stt_event, map}

  where the map contains at least:

  - "event" ("partial" | "final" | "error" | ...)
  - "session_id"

  """

  @type session_id :: String.t()

  @callback start_session(session_id(), pid(), keyword()) :: :ok | {:error, term()}
  @callback push_chunk(session_id(), String.t()) :: :ok
  @callback stop_session(session_id()) :: :ok
end
