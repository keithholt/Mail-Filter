# Local model-failure reproduction plan

Current release decision (October 28): after reviewing the completed defensive audit and clean Store/Dev qualification, the publisher explicitly approved submitting build 27. The exact invalid-response cause remains unreproduced. Earlier hold statements below record the investigation at that time; see [current release qualification](release-2.1.1.md).

Development and debugging take place on the publisher’s Mac. The remote family member is a beta tester, not a debugging resource. Do not require him to install Xcode, run source scripts, record Instruments traces, or provide repeated diagnostic sessions. No access to his Mac is assumed. A later optional beta check should be a brief normal-use test of a prepared build.

Store review remains on hold. The publisher requires a plausible reproduction before submitting a replacement update. Scripted empty replies and deliberately tiny token limits establish application behavior but do not establish the cause of the reported failure.

## Evidence available locally

The original support report records invalid first-attempt responses after about five to six seconds, followed by successful smaller-section retries. These were not application deadline expirations. The report did not retain raw reply bytes or token usage. An empty reply, hidden formatting, output truncation and a response-association error remain different hypotheses.

The development Mac is Apple M1 Max (MacBookPro18,2), 65,536 MiB, macOS 27.0.1 build 26A434. Both general and content-tagging queries reported AFM 3 Core, context 4,096 tokens and no reasoning capability. The remote Mac is reported as M3 Pro, 18 GiB and macOS 27.0.1; its actual selected model remains unknown. Do not infer it from memory or chip type.

Apple states that the public API cannot select the on-device model variant; the device and OS determine it. Consequently, this M1 Mac cannot be configured through that API to force a different hardware’s model. A VM, process memory limit or large memory allocation is not an established substitute. Do not manufacture memory pressure on the publisher’s working Mac. [Apple’s accepted answer](https://developer.apple.com/forums/thread/832555)

The local `./MacApp/probe-model.sh --environment` command performs no generation, Mail access, account lookup or email-file scan. The shared collector also has an optional standalone [Model Check helper](../MacApp/ModelCheck/README.md). Its local UI is tested; portable signing/notarization is paused and is not a prerequisite for this investigation.

## Historical local failures take priority

The [October 28 history audit](model-failure-history.md) confirms real context-limit and repeated invalid-response failures on this same host on October 12. The first retry implementation resent the same JSON payload; a later change added token planning and progressively smaller sections. Store build 18 retains that fix. The remote report’s first-invalid/smaller-retry-success sequence plausibly belongs to the same request-size-sensitive failure family, although the historical local response contract differed and failing bytes were not retained.

The subsequent [timing and queue investigation](timing-and-queue-investigation.md) records completed tests of those request shapes and full-duration native retry timing, plus the candidate build-26 corrections. Continue to prioritize that evidence before hardware speculation. The 80-trial fictional frozen-budget run exercised single-section inputs at most 2,008 tokens, not the historical context boundary or a four-section negative under the 20-second whole-attempt deadline. Preserve context-limit, invalid-response and actual timeout categories separately. Additional successful short controls cannot establish that the old problem is resolved.

## Local test sequence

1. Verify the evidence collector with deterministic checks, including partial multi-section failures and private journal retention.
2. Capture and repeat exact baseline requests locally, using fictional controls and any problematic email exports already available on the publisher’s Mac. Do not depend on obtaining another export from the beta tester. A locally forwarded copy is useful, but label it as a different input unless bytes match.
3. Compare one variable at a time: output budget, section size, then policy wording. Alternate AB/BA order with at least 20 repetitions per arm for a release-evidence run.
4. If a real failure occurs, retain the request, response, transcript and event journal immediately. Narrow it to an inference failure, a parser rejection or a later application gate before changing production code.
5. Exercise retries, deadlines, cancellation, duplicate callbacks, bursts and settings changes through the real Dev application pipeline with scripted transport and temporary stores. Keep this evidence separate from actual Foundation Models generation.
6. Qualify the sandboxed Dev/MailKit context locally in Preview using the Dev-only self-mail switch and a designated test inbox. Never enable two filters against the same working inbox. Use normal incoming test mail; do not assume importing an email file generates a received-message callback. Real moves are outside automated replay tests.
7. Only after local evidence supports a mitigation, offer a prepared beta build for a short normal-use check. The beta tester’s availability is not a dependency for steps 1–6. Submission still requires the publisher’s reproduction gate and authorization.

## Frozen-request replay runner

The new developer-only `--replay-local` mode links no Mail automation, settings store or action code. It requires an explicit single export path or fictional controls, plus a new output directory. It never sweeps Desktop. Parent directories must already exist, and an existing run directory is refused.

From the repository root, start with fictional controls:

```sh
./MacApp/probe-model.sh --check-replay
./MacApp/probe-model.sh --replay-local --synthetic-only \
  --output /private/tmp/mail-filter-budget-run --repetitions 20
```

This runs two fictional long messages, a political appeal and a receipt, 20 times for each of two arms: 80 message trials. The baseline requests are planned once with a 6,000-character maximum and a 64-token response reserve. Both arms then use the identical instructions and final prompts. Only the output limit changes from 64 to 256. If an unchanged request cannot fit the larger reserve, it is recorded as skipped; the runner does not secretly shorten it.

Compare section size separately:

```sh
./MacApp/probe-model.sh --replay-local --synthetic-only \
  --experiment section-size --output /private/tmp/mail-filter-section-run
```

Both arms retain the same policy and 64-token output limit. The second arm plans at most 3,000 characters per section. All eligible first-6,000-character content remains covered, with the production planner’s overlap and opening/closing context. A positive may finish early; a negative requires all sections. Compare policy wording separately using `--experiment policy`, which changes only the reconstructed previous ending versus the saved current policy, retaining the 6,000-character maximum and 64-token limit. Policy changes can themselves change token counts and therefore the section plan; inspect the manifest rather than treating that experiment as byte-identical input.

Use a locally exported message explicitly:

```sh
./MacApp/probe-model.sh --replay-local \
  --report '/private/path/to/selected-email.json' \
  --original-policy '/private/path/to/original-policy.txt' \
  --output /private/tmp/mail-filter-selected-run --repetitions 20
```

`--original-policy` supplies the exact old policy snapshot. Without it, the runner reconstructs the known previous standard ending from the saved policy and labels that provenance in the manifest. A custom saved policy is not automatically an exact build-18 baseline. The original wrapper, String interface, greedy generation, permissive transformation mode and original parser are preserved. Request planning uses the production engine’s tokenizer; no generation occurs while constructing the frozen plan.

Add `--plan-only` to save requests without generating. `--repetitions` accepts even numbers from 2 through 100; two is only a smoke test. Every run stores the exact schedule, with equally many AB and BA pairs and rotating fixture order. Fresh sessions do not prove the operating-system model was cold; token-count planning may load assets.

## Retained evidence and privacy

The output directory is mode 0700; generated files are mode 0600. It contains private email and prompt text if a real export is selected. Keep it outside Git and do not automatically upload it or attach it to support mail.

- `manifest.json`: exact instructions/prompts, exact-byte SHA-256 digests, input-file digest, source fingerprints, token counts, policy provenance, section plans and full trial order.
- `events.jsonl`: synchronized trial-start, section-start, section-finish and trial-finish records. A started request without a finish identifies interruption; earlier completed trials remain available.
- `trial-NNNN.json`: raw responses, UTF-8 bytes as base64, full Unicode scalars, old and current parser decisions on the same reply, timing, available input/output/reasoning usage, thermal state and Low Power Mode.
- Per-section transcript files: the session before inference and its final observable state on return/error. The completed response also retains a JSON transcript in the trial file. A killed process cannot save a reply it never observed.
- `results.json`: final retained outcomes and environment snapshot, queried after trials to avoid additional preflight model queries before generation. Interrupted runs can lack this final file while retaining earlier evidence.

The replay bounds each generation at 20 seconds and stops the experiment on timeout or cancellation. It does not retry into a potentially still-running inference or overlap trials. This request-level experiment is not a simulation of the production whole-attempt/total retry deadlines. Those paths have separate application tests. If the service stalls, the journal distinguishes the observation from a completed invalid label. No timeout settings in the shipping product change.

## Interpret results by layer

| Hypothesis | Local controlled test | Supporting evidence |
|---|---|---|
| Output budget truncates the label | Same frozen request, 64 versus 256 tokens | Invalid visible output with actual usage at the cap; higher cap repeatedly returns a whole label. |
| Presentation formatting breaks parsing | Both parsers examine one captured reply | Original parser rejects boundary bytes that the candidate accepts. Plain ASCII `political` must pass both. |
| Long input triggers failure | Same policy/cap, explicit large versus smaller section plans | Baseline repeatedly fails and smaller sections recover on that input, including negative controls requiring every section. |
| Loading or cache state matters | Normal first request after restart/idle versus repeats | Instruments loading/timing evidence correlates with failures. A new process alone is insufficient. |
| Application lifecycle or queue causes loss | Local NativeClassifier injection and Dev Preview | Callback, generation, retry and final gate evidence identifies the exact loss; no late result causes an action. |
| Hardware-specific model behavior | Local model identity and available traces | A hardware limitation is documented explicitly; a different model cannot be emulated by changing a response string or the app’s heap. |

If a captured response is plain valid `political` and both parsers accept its bytes, investigate response association, callbacks and final action gates. Adding verification words cannot fix a label parser failure. If reasoning usage is zero on local failures, do not attribute those failures to reasoning consuming the output budget.

Use the Foundation Models Instruments template on the publisher’s Mac when a local failure is reproducible. Apple documents model loading, instructions, responses, token consumption and latency. Compare profiled and unprofiled runs because instrumentation can change timing. Traces and transcripts may contain unencrypted email; preserve them privately. Uploading a reproduction to Apple is a separate publisher decision.

## Completion and release gate

Success requires a plausible actual baseline failure, retained layer-specific evidence and a targeted mitigation that succeeds against that case under repeated comparison while ordinary mail stays negative. A scripted first-empty/second-valid sequence demonstrates recovery but does not prove why Apple returned an invalid first result. Earlier 16- and 48-trial suites passed; the one-/two-token truncation controls failed only at artificial limits. None satisfies the original reproduction gate.

If all local requests keep succeeding, record that limit candidly. Do not claim identical M3 behavior or make the beta tester responsible for finishing the investigation. Decide with the publisher whether additional hardware access is justified or the release criterion should change; elapsed time and extra passing controls do not silently waive it.

## Primary references

- [Apple: model selection is determined by device and OS](https://developer.apple.com/forums/thread/832555)
- [SystemLanguageModel and model variants](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Output limits can terminate generation without throwing](https://developer.apple.com/documentation/foundationmodels/generationoptions/maximumresponsetokens)
- [Foundation Models performance analysis in Instruments](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
- [Inspecting and exporting session transcripts](https://developer.apple.com/documentation/foundationmodels/inspecting-session-transcripts-and-reporting-model-feedback)
