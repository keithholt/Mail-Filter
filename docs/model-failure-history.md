# Historical investigation of model failures

Investigated October 28, 2026 from Git history and the publisher’s retained October 12 diagnostic report, alongside the remote beta tester’s build-18 support report. Times below use America/Los_Angeles. Private reports, email content and message identity digests are excluded from this document and Git.

## Finding

The publisher’s Mac had real model context-limit and invalid-response failures before the remote Mac was involved. Smaller-section retries were introduced in response to those local problems. The remote report is therefore plausibly another occurrence of an existing request-size/response-generation problem. There is no evidence yet that different RAM capacity or a different model variant is required to explain it.

The inspected historical reports do not establish a common underlying cause: the original local invalid response was generated under a JSON contract, while build 18 expects a whole string label. Neither report retained the failing reply bytes or actual generation usage. Similar elapsed time and successful smaller requests are useful clues, not proof of identical failures.

## What the local report actually records

One build-10 diagnostic report was pasted repeatedly; eight retained attachments have identical SHA-256 digests. They are one observation set, not eight independent reproductions.

| Local event, October 12 | Retained evidence | What is established |
|---|---|---|
| 13:20:11.749–13:20:12.839 | `analysisStarted`, then `review modelContextLimit`, attempt 1; `FoundationModels.LanguageModelError` | A real model context-limit error on this host after 1.090 seconds. The first retry implementation treated that error as terminal. |
| 14:00:11.939–14:00:17.955 | Attempt 1 ends with `retryScheduled invalidModelResponse` | The returned response failed the then-current JSON parser after 6.016 seconds. Raw response content was not retained. |
| 14:00:19.017–14:00:24.018 | Attempt 2 ends with the same category | The same payload was retried and failed after 5.001 seconds. |
| 14:00:26.184–14:00:31.104 | Attempt 3 ends with `review invalidModelResponse` | The third attempt failed after 4.920 seconds; the message was retained. |

That report contains no `modelTimedOut` entries. This does not establish that timeouts never occurred in other sessions. It establishes that these particular recorded failures completed well before the application’s 20-second attempt deadline. The context error and invalid-response sequence are separate recorded jobs.

## Git chronology

| Commit, local date/time | Implementation change | Connection to the failure |
|---|---|---|
| [140d3e9](https://github.com/keithholt/Mail-Filter/commit/140d3e9), October 11, 15:49 | Native MailKit app; one free-form JSON response with decision, explanation and evidence. No bounded classification retry wrapper. | Generation and parse failures left messages in place. |
| [00b9e1c](https://github.com/keithholt/Mail-Filter/commit/00b9e1c), October 12, 11:19 | Added three attempts, fresh sessions, 20 seconds per attempt, 1-/2-second retry delays and a 60-second total limit. | Every attempt still sent the same bounded email payload. Context-limit errors were explicitly nonretryable. This could not repair an oversized request by retrying it. |
| [29b68fe](https://github.com/keithholt/Mail-Filter/commit/29b68fe), October 12, 16:17 | Added token counting, bounded request planning, overlapping sections, and retry section caps of 6,000 → 3,000 → 1,500 characters. Context-limit errors became retryable in the native/selected-message callers. Removed account/recovery metadata from the model prompt. | This is where retries first changed the request size instead of repeating the same oversized request. It retained coverage of the first 6,000 body characters. The same commit replaced free-form JSON parsing with guided decision/reason generation. |
| [df807d3](https://github.com/keithholt/Mail-Filter/commit/df807d3), October 12, 18:12 | Replaced guided generation with one plain String label under permissive transformations. Reduced the output reserve from 256 to 64 tokens. Kept token planning and smaller-section retries. | The intervening guided interface had refused political examples in local controlled comparisons. The recorded string-interface comparison succeeded on the exported political example, a synthetic receipt and a synthetic campaign appeal. The change did not demonstrate a general cure for every length-sensitive failure. |
| [8a29920](https://github.com/keithholt/Mail-Filter/commit/8a29920), October 19, tagged `v2.1.0-app-store-submission` | Original Store build 18. | Includes the 6,000/3,000/1,500 section-cap sequence, 64 output tokens, three attempts and 20-/60-second deadlines. The retry mechanism was present in the released Store app. |
| [9be2a05](https://github.com/keithholt/Mail-Filter/commit/9be2a05), October 27, 21:33 | Candidate builds start with 3,000-character sections, then 1,500/1,500; output reserve restored to 256; stronger parser and numeric diagnostics. | Bounded mitigations awaiting qualification. The 20-/60-second limits did not change. |

`AnalysisDeadline.swift` has the same Git blob from its introduction in `00b9e1c` through the original Store tag and the current source. The retry deadline constants also remain 20 and 60 seconds. That establishes source continuity, not proof that every asynchronous deadline race is correct.

## Comparison with the beta tester’s report

On October 27 at about 19:27 local time, build 18 recorded two relevant sequences:

| Observation | First message | Second message |
|---|---|---|
| First attempt | One section; invalid response after about five seconds | One section; invalid response after about six seconds |
| Retry | Four sections; completed not-political | Four-section plan; first section political, requested Junk |
| Retry delay | Approximately one second | Approximately one second |

These sequences demonstrate that the released smaller-section retry mechanism ran and recovered. They do not contain raw replies, input/output/reasoning token usage, or measured memory pressure. Build 18 grouped an empty reply and a nonempty invalid label under `invalidModelResponse`. `other:1` is the app’s sanitized error domain/code, not evidence of a low-memory error or an Apple model crash.

The local October 12 sequence did not have smaller-section retries yet and exhausted all three identical-payload attempts. The later remote sequence did have them and recovered. That difference fits the intended purpose of the local fix. A shared underlying request-size sensitivity remains plausible; its exact mechanism remains unproven.

The guided-interface refusal regression is a separately established historical issue. Store build 18 already uses the corrected String interface, so reintroducing guided generation would not be a justified remedy for the current symptom.

## Consequences for the next local tests

The investigation should start from the known local failure history. Hardware/model differences remain possible test variables, without making them the leading explanation or a prerequisite for progress.

1. Preserve three distinct outcomes: explicit context overflow, completed invalid/empty response, and application deadline expiration. A five-second invalid response must not be treated as a 20-second timeout.
2. Reconstruct the historical request contracts locally: pre-splitting JSON and the released String interface. Use any original local export/policy snapshot already available. If the exact original payload is missing, label a substitute as a constructed case rather than an exact historical replay.
3. Include token-dense content near the model’s context boundary, long forwarded messages and ordinary long negative controls. Retain exact instructions, prompt bytes and source fingerprints. Confirm what changed between one large request and the smaller section plan.
4. Run the actual native retry wrapper with real 20-second attempt and 60-second overall limits and actual 1-/2-second delays. Exercise complete multi-section negatives, positives in later sections, completion near deadlines, late replies and the next queued message. Small scripted tests remain useful for broad coverage, but cannot substitute for full-duration timing qualification.
5. Measure whole-attempt time as well as individual generation time. The attempt deadline includes token planning and all sections. Smaller requests can generate faster individually while requiring more calls; a negative must finish every section. The 60-second overall deadline includes retry delays but begins after queue admission.
6. Keep inference-only, native-pipeline and MailKit Preview evidence distinguishable. No automated historical experiment should move real mail or disturb the working Store installation. Remote beta testing remains optional normal use after local work supports a mitigation.

The latest 80-trial frozen-budget run used two fictional controls, each of which fit in a single section, with at most 2,008 actual input tokens. All succeeded. That run validates repeatability and evidence capture for those cases; it does not exercise the historical near-context failure or a four-section negative competing with the whole-attempt deadline.

The original failure has not yet been reproduced with retained raw response/usage evidence under the released String contract. The publisher’s Store review hold remains in effect. This historical audit corrects the investigation’s emphasis; it does not establish a new production fix or justify longer timeouts.

## Evidence retained privately

A local audit index under ignored `.build/model-replays/history-audit-2026-10-28.json` records the source-report paths/digests, exact supporting Git objects and relevant numerical observations. It contains no copied message bodies and is not part of the public documentation. Git history establishes the implementation changes; the retained reports establish runtime observations. The original bad response bytes cannot be recovered from a log that never saved them.
