defmodule SttPlayground.STT.PartialMerge do
  @moduledoc false

  @max_overlap_words 12
  @replace_prefix_min_words 3

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

      String.starts_with?(prev, incoming) ->
        prev

      true ->
        prev_words = words(prev)
        incoming_words = words(incoming)

        # If the provider is sending a full-utterance hypothesis that refines
        # the previous one (common prefix, small changes at the end), prefer
        # replacing instead of appending.
        prefix_len = common_prefix_len(prev_words, incoming_words)

        cond do
          prefix_len >= @replace_prefix_min_words ->
            # Avoid going backwards if incoming is just a shorter prefix.
            if String.starts_with?(prev, incoming) and length(prev_words) > length(incoming_words) do
              prev
            else
              incoming
            end

          true ->
            overlap = max_overlap(prev_words, incoming_words)

            cond do
              overlap > 0 ->
                (prev_words ++ Enum.drop(incoming_words, overlap))
                |> Enum.join(" ")
                |> String.trim()

              true ->
                # No clear relation: prefer latest hypothesis to avoid runaway repetition.
                incoming
            end
        end
    end
  end

  defp words(text) do
    text
    |> String.split(~r/\s+/, trim: true)
  end

  defp common_prefix_len(a_words, b_words) do
    max_k = min(length(a_words), length(b_words))

    Enum.reduce_while(0..(max_k - 1), 0, fn idx, _acc ->
      a = normalize_word(Enum.at(a_words, idx))
      b = normalize_word(Enum.at(b_words, idx))

      if a != "" and a == b do
        {:cont, idx + 1}
      else
        {:halt, idx}
      end
    end)
  end

  defp normalize_word(word) when is_binary(word) do
    word
    |> String.downcase()
    |> String.replace(~r/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/u, "")
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
