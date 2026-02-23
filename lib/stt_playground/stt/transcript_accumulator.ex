defmodule SttPlayground.STT.TranscriptAccumulator do
  @moduledoc """
  Maintains a stable, always-growing transcript from a stream of STT updates.

  Streaming STT usually produces two kinds of updates:

  - **interim** hypotheses (volatile; may jump around / regress)
  - **final** segments (stable; only grows)

  This module keeps them separate so UIs can render either:

  - `stable_text/1`: only finalized text (monotonic)
  - `display_text/1`: stable + current interim (can flicker at the tail)
  """

  defstruct final_segments: [], interim: ""

  @type t :: %__MODULE__{final_segments: [String.t()], interim: String.t()}

  def new, do: %__MODULE__{}

  @spec ingest(t(), String.t() | nil, boolean()) :: t()
  def ingest(%__MODULE__{} = state, content, is_final) do
    content = (content || "") |> to_string() |> String.trim()

    cond do
      content == "" ->
        state

      is_final ->
        # Avoid duplicating consecutive identical final segments.
        final_segments =
          case List.last(state.final_segments) do
            ^content -> state.final_segments
            _ -> state.final_segments ++ [content]
          end

        %__MODULE__{state | final_segments: final_segments, interim: ""}

      true ->
        %__MODULE__{state | interim: content}
    end
  end

  @spec stable_text(t()) :: String.t()
  def stable_text(%__MODULE__{} = state) do
    state.final_segments
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.trim()
  end

  @spec interim_text(t()) :: String.t()
  def interim_text(%__MODULE__{} = state), do: String.trim(state.interim)

  @spec display_text(t()) :: String.t()
  def display_text(%__MODULE__{} = state) do
    [stable_text(state), interim_text(state)]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.trim()
  end
end
