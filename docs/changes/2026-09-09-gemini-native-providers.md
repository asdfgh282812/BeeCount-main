# Native Gemini custom providers

## Why

The Gemini speech branch still used OpenAI-compatible `chat/completions` with
`input_audio`; text and vision ignored the configured API family. Gemini custom
providers now use Google's native `generateContent` endpoint for all three
capabilities, including capability validation.

## Changes

- `lib/ai/providers/ai_provider_config.dart` and `ai_provider_manager.dart` retain
  the existing `apiFamily` persistence, defaulting legacy and built-in providers
  to `openai`. No storage migration or Riverpod changes are required.
- `lib/ai/providers/ai_provider_factory.dart` shares Gemini transport and response
  parsing. Request fields use `contents`, `systemInstruction`, `inlineData`,
  `mimeType`, and `generationConfig`. Each Gemini request owns its Dio instance,
  uses 60-second connect and 120-second send/receive timeouts, and closes it after
  completion. OpenAI and built-in Zhipu requests keep their existing paths.
- Native URLs remove redundant path slashes and a trailing `openai` or `models`,
  accept model IDs with a `models/` prefix, and supply `v1beta` for a host-only
  base. Custom proxy hosts and path prefixes are preserved.
- Authentication uses only `x-goog-api-key`, as confirmed by the user. Query
  parameters and fragments are not carried into generated URLs. Raw Base URLs
  are no longer printed during validation; native request logs show the
  normalized URL without the key. Header plus query authentication was
  deliberately rejected because it would reintroduce URL-log exposure.
- Response parsing joins non-thought text parts from the first candidate.
  Empty/non-text parts and empty candidate lists return an empty STT result;
  text and vision require nonempty output. Prompt blocking, safety stops, and
  malformed responses fail explicitly rather than passing as silent audio.
  Google error codes, statuses, and messages are retained.
- The editor offers localized OpenAI/Gemini Native segments, fills an empty
  Gemini base with `https://generativelanguage.googleapis.com/v1beta`, and uses
  `gemini-3.5-flash` as the requested hint for all three models. Hints are not
  saved as model selections. Existing URLs/models are preserved. Switching
  family clears validation results and is disabled while testing or saving.

## Verification And Limits

Local HTTP tests cover validation and bound runtime calls, request fields,
authentication, URL normalization, empty responses, safety blocks, error parsing,
configuration persistence, and the existing OpenAI chat path. Widget tests cover
the family switch at a narrow viewport, model hints, preserved values, and the
absence of a switch for built-in providers.

No production key is used by the tests. Live Google acceptance, model availability,
and recognition quality still depend on the user's chosen model and account.
Media is sent inline with MIME types selected from file extensions; this change
does not add transcoding, file signature inspection, Files API uploads, or
streaming. The existing recording path supplies WAV audio.

References:
- https://ai.google.dev/api/generate-content
- https://ai.google.dev/gemini-api/docs/api-key