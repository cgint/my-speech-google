defmodule SttPlayground.STT.PartialMerge do
  @moduledoc false

  @max_overlap_words 12

  @doc """
  Merges a stream of partial transcripts into a growing transcript.

  Some streaming STT providers emit interim results as a sliding window, e.g.:

      "hello there"
      "there what is"
      "what is going on"

  This function merges them into:

      "hello there what is going on"
  """
  @spec merge(String.t(), String.t()) :: String.t()
  def merge(prev, incoming) when is_binary(prev) and is_binary(incoming) do
    prev = String.trim(prev)
    incoming = String.trim(incoming)

    cond do
      incoming == "" ->
        prev

      prev == "" ->
        incoming

      String.starts_with?(incoming, prev) ->
        incoming

      true ->
        prev_words = words(prev)
        incoming_words = words(incoming)

        overlap = max_overlap(prev_words, incoming_words)

        merged_words = prev_words ++ Enum.drop(incoming_words, overlap)

        merged_words
        |> Enum.join(" ")
        |> String.trim()
    end
  end

  defp words(text) do
    String.split(text, ~r/\s+/, trim: true)
  end

  defp max_overlap(prev_words, incoming_words) do
    max_k = min(length(prev_words), length(incoming_words))
    max_k = min(max_k, @max_overlap_words)

    # Find the largest k such that suffix(prev, k) == prefix(incoming, k)
    Enum.reduce_while(max_k..1//-1, 0, fn k, _acc ->
      if suffix(prev_words, k) == prefix(incoming_words, k) do
        {:halt, k}
      else
        {:cont, 0}
      end
    end)
  end

  defp prefix(list, k), do: Enum.take(list, k)
  defp suffix(list, k), do: list |> Enum.drop(length(list) - k)
end
