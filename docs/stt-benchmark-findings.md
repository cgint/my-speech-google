# STT benchmark findings (toy clips)

Date: **2026-03-08**

This document records *repeatable* file-in → text-out comparisons between:
- **Google Cloud Speech-to-Text v2** (batch `recognize` and streaming replay)
- **Gemini multimodal audio transcription** (via `google-genai`)

It is intended as durable project know-how for future sessions.

## Quick summary (what matters)

- **Best speed/quality trade-off (so far):** Google STT v2 **batch** (`recognize`) — fastest and generally accurate.
- **Main quality issue observed:** Google STT often **normalizes** certain tokens (e.g. `Feinart` → `Fine Art`) and can distort internal proper nouns (e.g. `VoxMLX` → `Fox MLX`).
- **Gemini advantage observed:** Gemini more often preserved `Feinart` as a single token (closer to the German original), but still struggled with unusual internal names.
- **Streaming latency caveat:** our Google “stream replay” timings are **not representative** of real mic streaming UX; on short files they are dominated by stream/session setup overhead.

## What was built for the comparison

### Scripts (repo root)

- `./stt_file_google.py`
  - `--mode recognize` (batch; auto-decoding)
  - `--mode stream` (streaming replay; **WAV PCM16 16kHz mono only**)
  - Transcript on stdout; timings/metadata on stderr.

- `./stt_file_gemini.py`
  - Uploads audio via File API, then `generate_content()` with an instruction to return transcript only.
  - Transcript on stdout; timings/metadata on stderr.

### Benchmark audio set

- Directory: `bench_audio/`
- Manifest: `bench_audio/manifest.tsv` (expected text + language hint)

All WAVs are:
- PCM16 (`pcm_s16le`)
- 16,000 Hz
- mono

Generated via macOS:
- `say -v <Voice> -o out.aiff "..."`
- `ffmpeg -i out.aiff -ac 1 -ar 16000 -c:a pcm_s16le out_16k_mono_pcm16.wav`

### Convenience runner

- `./bench_compare.sh` runs per case:
  - Google STT v2 recognize
  - Google STT v2 stream replay
  - Gemini (if `GEMINI_API_KEY` / `GOOGLE_API_KEY` is set)

## Models and configuration used

### Google Cloud STT v2
- Endpoint: derived from `STT_LOCATION` (default used: `eu`)
- Model: `STT_MODEL` default used in scripts: **`chirp_3`**
- Languages: `STT_LANGUAGE_CODES` set from `manifest.tsv` “lang_hint”

### Gemini multimodal
- Model used in measurements: **`gemini-3.1-flash-lite-preview`**
- Auth: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)

Note: The SDK sometimes prints a warning about non-text response parts (`thought_signature`). We ignore it and extract the text parts.

## Reproduction

Run all benchmark cases:

```bash
./bench_compare.sh
```

Run a single case manually:

```bash
export STT_LANGUAGE_CODES=de-DE
./stt_file_google.py bench_audio/de_3sent_anna_16k_mono_pcm16.wav --mode recognize
./stt_file_google.py bench_audio/de_3sent_anna_16k_mono_pcm16.wav --mode stream
./stt_file_gemini.py  bench_audio/de_3sent_anna_16k_mono_pcm16.wav
```

## Results (timings + transcript deltas)

All timings are “wall clock” times printed by the scripts for that specific run.

### Table: timings by case

| case id | Google recognize | Google stream replay | Gemini (file) |
|---|---:|---:|---:|
| `de_short_anna` | 832.1 ms | 2957.5 ms | 3429.0 ms |
| `de_long_anna` | 1256.5 ms | 8572.9 ms | 4172.0 ms |
| `en_short_samantha` | 919.6 ms | 2827.2 ms | 3827.1 ms |
| `mixed_anna` | 934.4 ms | 5626.7 ms | 4538.2 ms |
| `de_3sent_anna` | 1031.0 ms | 8141.0 ms | 3728.3 ms |
| `en_3sent_samantha` | 1010.8 ms | 9092.9 ms | 4393.7 ms |
| `de_3sent_propernouns_anna` | 1294.4 ms | 11542.2 ms | 3677.9 ms |

### Notable transcript differences (qualitative)

**A) German “Feinart-Produktion” token**
- Expected: `Feinart-Produktion`
- Google STT (batch + stream): typically `Fine Art Produktion` (normalization/segmentation + partial anglicization)
- Gemini: typically `Feinart Produktion` (kept `Feinart`, hyphen removed)

**B) Mixed language formatting normalization**
- Expected contained: `A B C`
- Google STT and Gemini both produced: `ABC`

**C) Proper noun / internal technical words (synthetic TTS audio)**
Case: `de_3sent_propernouns_anna`
- Expected: `VoxMLX`, `SttPlayground`, `Phoenix LiveView`, `Elixir`
- Google STT example output:
  - `VoxMLX` → `Fox MLX`
  - `SttPlayground` → `STT Playgrund`
  - `LiveView` → `Live View`
  - `Elixir` → `Elixier`
- Gemini example output:
  - `VoxMLX` → `Fox MLX`
  - `SttPlayground` → distorted (e.g. `STT Bleigrund`)
  - `LiveView` → `Live View`
  - `Elixir` stayed `Elixir` in that run

## Interpretation and next steps

- Treat these as **baseline**/repeatability tests; they are synthetic macOS TTS audio.
- Validate with **real microphone** recordings (noise, accent, speed) before deciding.
- Regardless of provider, plan for a **context-aware post-processing layer**:
  1) safe mechanical normalization
  2) deterministic domain dictionary corrections
  3) optional gated LLM pass for “verbatim correction” on trigger terms / low confidence
- If Google STT stays the default, evaluate:
  - phrase hints / custom vocabulary for domain terms
  - potentially separate language configs for mixed-language sessions
