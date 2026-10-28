# Reproduce the affected Mac's classification failure

The next experiment must reproduce a real first-attempt failure under the original classification contract and then demonstrate a mitigation on that same input. More injected empty replies or more successful fictional examples on the current Mac cannot establish that result. Store review remains on hold. This plan does not install an app, change settings, send mail or authorize access to another person's Mac.

## Establish which model is actually running

The October 27 preflight on the development Mac reported:

| Variable | Observed value |
|---|---|
| Hardware | Apple M1 Max, MacBookPro18,2 |
| Physical memory | 65,536 MiB |
| macOS | 27.0.1, build 26A434 |
| General model | AFM 3 Core |
| Content-tagging model | AFM 3 Core |
| Reasoning capability | false for both use cases |
| Context | 4,096 tokens for both use cases |

The affected Mac is reported as M3 Pro with 18 GiB and macOS 27.0.1. Its exact OS build, selected model variant and reasoning capability have not been captured. Apple exposes both Core and Core Advanced variants. Do not infer its selected variant from its chip, installed RAM or OS version. Matching those reported version numbers does not yet establish equivalent model environments.

Run this preflight from the same source revision on both Macs:

```sh
./MacApp/probe-model.sh --environment
```

It prints model variants, availability, context sizes and reasoning support for the general and content-tagging use cases, together with hardware, OS build, language, locale and Low Power Mode. It performs no generation and reads no Mail, account settings or Desktop reports. It records no host name or serial number. Comparisons also include this environment object automatically, captured after their trials to avoid extra preflight model queries before the first request. For a cold/loading experiment, run the separate preflight after that first trial, not immediately before it; use Instruments to establish loading state. Running from source requires Xcode command-line tools with the current Foundation Models SDK; the command is not part of the installed Store tool.

First compare the two JSON outputs. A different model variant is a test variable, not proof that it caused the failure. A matching display name is also not an exact model-asset revision identifier. Preserve the full OS build and any later session/profile evidence.

## Obtain the actual failing input

On the affected Mac, export the original problematic message with **Export selected email report**. Keep that private JSON and the accompanying support report outside Git. The export supplies the RFC source, extracted text, sender, subject, current policy and retained automatic history. Record the installed app/extension build and whether the policy was edited. Do not forward it again to produce the fixture: forwarding can change the model input even when the message remains readable.

Record SHA-256 digests of the original export, exact decoded excerpt, instructions and each final prompt. Preserve their bytes locally so the two Macs can replay the same request. A hash alone cannot reconstruct missing content. If the old automatic reply was not retained, a later positive manual analysis cannot recover that lost reply; reproduce a new failure with explicit capture.

Use the failing message, a second previously failing message, an ordinary receipt and a short political appeal as the initial corpus. Synthetic controls establish that labeling still works. The actual failing input is the principal case.

## Keep reproduction separate from shipping changes

Use a standalone read-only replay first. It needs no Mail connection, extension activation, account credentials, protection reset or replacement of the Store app. Run on the affected physical Mac before attempting to emulate its resource conditions elsewhere. If source tools are unavailable, prepare a Developer ID signed and notarized replay helper; do not require the recipient to enroll as a developer or weaken Gatekeeper. The signed Development app has device-provisioning requirements and is not automatically a portable helper for another Mac.

The current budget comparison can begin with an explicit export path:

```sh
./MacApp/probe-model.sh --compare-request-budgets '/private/path/to/affected-email.json'
```

That command compares section/output budgets and records the environment, labels, raw selected response, response scalars, timings and available token usage. Its default comparison uses the report's saved policy, not necessarily the original untouched build-18 policy. The stress mode reconstructs the previous standard ending for its baseline and records policy digests. Its original synthetic suite verifies that standard digest. A custom policy requires an explicit original snapshot before calling a run an exact baseline.

These existing comparisons are a starting point, not the finished experiment. The next replay runner needs the following properties before using it to attribute a cause:

- Preserve the original wrapper, String response interface, greedy sampling, permissive transformation setting, original policy and old whole-label parser. Parse each captured reply with both old and candidate parsers, without regenerating it.
- Capture the exact instructions/prompt and session transcript for each request in an explicit private export. Record UTF-8 bytes/scalars, input/output/reasoning usage, request duration, section plan and cancellation/error state. Keep raw captures out of routine support logs.
- Persist a trial-start record before inference and its outcome immediately after completion, so a stalled run or helper termination does not erase the earlier evidence. The current probe saves its report at the end and does not meet this crash-evidence requirement.
- Repeat one fixed failing input at least 20 times, counterbalancing baseline/candidate order. The earlier 48-trial suite repeats each combination twice in a fixed order; it is not a 48-repeat test of the affected email.
- Freeze the final prompt when varying only output limits. Larger output reserves can change the current planner's section boundaries, confounding that comparison. Compare 64, 256 and, if the unchanged input fits, 512 or 1,024 output tokens; skip incompatible combinations rather than silently shortening the prompt.
- Change section length, policy ending, use case or reasoning level in separate experiments. Use supported reasoning controls only when the model reports that capability. A content-tagging String trial is different from the historical guided-schema tagger, which reintroduced guardrail refusals.

## Test hypotheses with observable outcomes

| Hypothesis | Controlled comparison | Evidence that would support it |
|---|---|---|
| Reasoning consumes a small output budget | Same exact prompt, model and settings; change only the response limit, then supported reasoning level separately | Invalid/empty visible reply with output/reasoning usage at the cap; a larger budget consistently restores a label without changing input. |
| The old parser rejects valid presentation formatting | Run both parsers over the same captured bytes | Old parser rejects a whole label with documented boundary formatting; candidate accepts it. No model rerun is needed. |
| Long input triggers the failure | Hold policy, use case and output limit constant; change section plan explicitly | Original full request repeatedly fails while the smaller plan succeeds, including negative controls requiring every section. |
| Model loading or cache state matters | First request after a normal restart/idle period versus subsequent requests | Instruments shows loading/latency or different response behavior correlated with the failure. A fresh app session alone does not prove a cold model. |
| Runtime resources matter | Same physical Mac/input under ordinary idle and ordinary workload conditions | Recorded pressure/thermal/token/latency changes correlate with repeated failures; installed memory alone is insufficient. |
| Host/extension context matters | Same frozen input in standalone replay, sandboxed Dev host and MailKit Preview | Failure appears in a specific execution context with matching request/model fingerprints. |

If the affected Mac also reports Core without reasoning, or failed replies show zero reasoning tokens, reduce the priority of the reasoning-budget hypothesis. If a response contains plain valid ASCII `political` and the old parser accepts those exact bytes, investigate how that response became associated with the reported failure instead of continuing to blame keyword parsing.

## Trace one failure through Apple's tools

Use the Foundation Models template in Instruments on a designated test session. Apple documents request instructions, responses, token consumption, model loading and time-to-first-token views. Save the session transcript alongside the app-side event timeline. Compare unprofiled and profiled runs because instrumentation can alter timing.

Traces and transcripts can contain the email and prompt in unencrypted form. Keep them private. Capture them deliberately for the selected reproduction; do not silently add full transcripts to normal filtering logs or upload them to Apple. A Feedback Assistant submission would be a separate publisher decision.

For a model failure that reproduces without Mail, this trace can distinguish a framework-generated empty/truncated response from an application parser rejection. If the model succeeds outside MailKit, continue to the delivery/runtime stage rather than treating the standalone pass as resolution.

## Reproduce the MailKit context only when necessary

Use a separate macOS test user and a designated IMAP test inbox on the affected or equivalent physical hardware. Confirm the model is Ready and record its variant again in that user. Use the isolated Dev identifiers, Preview mode and the Dev-only own-mail switch where appropriate; do not enable both working-inbox filters together.

Replay source fixtures into the test inbox using a controlled ingestion method, and verify MailKit actually produces body-requested/body-ready callbacks. Do not assume dragging an email file into Mail or importing a mailbox produces received-message callbacks. An IMAP append mechanism is a candidate to qualify, not an already validated callback source. Preserve original subject/sender/body for a model comparison; a fresh Message-ID can avoid test deduplication because it is excluded from the classification prompt. Delivery recipients may need test routing changes, which must be recorded separately.

Start with a single message, then a small burst, then idle/wake/restart cases. Preview must report intended actions without moving mail. Only after callback, inference and final-gate behavior are understood should a disposable test inbox exercise actual Junk actions. Do not clear real recovery records or repeatedly reprocess working-inbox mail to obtain a failure.

## Limits of emulation and release evidence

An 18 GiB VM or memory allocation on the M1 Max is not automatically an M3 Pro reproduction. Before relying on a VM, prove that Foundation Models is available and selects an equivalent variant there. Restricting the helper's address space does not establish a machine-wide memory limit for the framework and its services. Do not manufacture pressure on the user's working Mac. A separate macOS user isolates app settings and accounts, not physical RAM or all operating-system model caches.

Success means retaining a real baseline failure, identifying which layer failed, and showing that one targeted change resolves that same case under counterbalanced repeats while ordinary mail stays negative. If the original failure no longer occurs, record that result and the changed environment; do not relabel injected faults or a one-token truncation control as the missing reproduction. Review stays on hold until the publisher's stated requirement is met.

## Primary references

- [SystemLanguageModel and model variants](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Output limits can terminate generation without throwing](https://developer.apple.com/documentation/foundationmodels/generationoptions/maximumresponsetokens)
- [Foundation Models performance analysis in Instruments](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
- [Inspecting and exporting session transcripts](https://developer.apple.com/documentation/foundationmodels/inspecting-session-transcripts-and-reporting-model-feedback)
