# “Google Interactions” — reality check

`TASK_speech_google_IDEA.md` mentions “Google Interactions” as intriguing.

Several web-search summaries (LLM-generated) claimed there is an official “Interactions API”, but **we do not currently have strong evidence** for a concrete public API with that name.

## Evidence we have

- A claimed REST endpoint URL returned **404** when checked from this environment:
  - `https://ai.google.dev/api/rest/v1beta/interactions` → 404

So: treat “Interactions API” as **unconfirmed / likely mislabeling** until we pin down an official product page.

## Likely interpretations (hypotheses)

1) **Gemini Multimodal Live API** (confirmed public docs)
- https://ai.google.dev/gemini-api/docs/multimodal-live
- It is literally about “interactions” (stateful, realtime), but isn’t branded “Interactions API”.

2) **Vertex AI Agent Builder / Conversational Agents**
- These are product families for building agents/bots.
- They may be what “Interactions” was meant to refer to (needs clarification).

## What we should do next (to de-risk)

- Decide whether the intent behind “Interactions” was:
  - (A) “I want a realtime voice session API” → likely Gemini Live
  - (B) “I want a managed agent framework/workflows” → likely Vertex AI Agent Builder
- If you remember where you saw “Google Interactions”, paste the link or name; then we can ground the choice.
