#!/usr/bin/env bash
set -euo pipefail

# Compare Google Cloud STT v2 vs Gemini multimodal on the benchmark WAVs.
# - Transcript goes to STDOUT
# - Diagnostics/timings go to STDERR (from the underlying scripts)

MANIFEST="bench_audio/manifest.tsv"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing $MANIFEST" >&2
  exit 2
fi

have_gemini=0
if [[ -n "${GEMINI_API_KEY:-}" || -n "${GOOGLE_API_KEY:-}" ]]; then
  have_gemini=1
fi

# Skip header / blank lines
awk -F'	' 'NR>1 && $1!="" {print $1"\t"$2"\t"$4}' "$MANIFEST" | while IFS=$'\t' read -r id wav lang_hint; do
  echo ""
  echo "============================================================"
  echo "CASE: ${id}"
  echo "FILE: ${wav}"
  echo "LANG_HINT: ${lang_hint}"
  echo "============================================================"

  echo ""
  echo "[Google STT v2] recognize"
  (export STT_LANGUAGE_CODES="$lang_hint"; ./stt_file_google.py "$wav" --mode recognize)

  echo ""
  echo "[Google STT v2] stream"
  (export STT_LANGUAGE_CODES="$lang_hint"; ./stt_file_google.py "$wav" --mode stream --chunk-ms 100)

  if [[ "$have_gemini" -eq 1 ]]; then
    echo ""
    echo "[Gemini] file"
    ./stt_file_gemini.py "$wav"
  else
    echo ""
    echo "[Gemini] skipped (set GEMINI_API_KEY or GOOGLE_API_KEY)"
  fi

done
