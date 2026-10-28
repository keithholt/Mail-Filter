# Model reliability qualification for builds 24 and 25

This records the application changes and local qualification for the replacement 2.1.1 update. The publisher withdrew build 23. The original Store version remains 2.1.0 build 18. Build 24 was uploaded but not submitted. The publisher requires a plausible reproduction of the affected Mac's failure before any replacement review submission. This gate remains unmet. Build 25 adds the local Dev-only self-mail test switch; it has not been uploaded.

## Evidence and limits

The second Mac's support report records invalid first-attempt responses after approximately five to six seconds, followed by successful smaller-section retries. These were not recorded application deadline expirations. Its earlier report did not include rejected response bytes, output/reasoning usage or memory-pressure measurements, so it cannot establish whether the model returned empty content, a truncated answer or unexpected formatting. Installed memory capacity alone does not establish a cause.

The local synthetic comparison does not reproduce the reported failure. Sixteen trials, covering short and long receipts and political appeals at 6,000/3,000-character sections and 64/256 output tokens, all produced the expected labels. No output limit was reached and local reasoning-token usage was zero. These observations do not prove the same behavior on the 18 GiB Mac. Smaller sections can increase total time for negatives that require every section, while a positive can finish early.

## Implemented changes

- Start at at most 3,000 characters per section, retry at 1,500, and keep the first 6,000 body characters eligible with overlapping context. Reserve 256 output tokens rather than 64. These are bounded mitigations, not a confirmed root-cause fix.
- Parse whole labels with harmless boundary formatting, including byte-order and directional marks, without accepting explanatory text, embedded labels or negation changes.
- Remove the bundled policy's request for a short explanation, which conflicts with the classifier's one-label response contract. Upgrade only recognized untouched standard prompts; custom policies remain unchanged. This removes a possible source of confusion without establishing the original failure's cause.
- Distinguish empty/blank output from a nonempty invalid label. Record elapsed time, request sizes and token budgets; on macOS 27, include actual input/output/reasoning counts. Record physical memory, thermal state and observed memory-pressure notifications without inferring pressure when unknown.
- Record body-callback latency and pending body requests from retained history. Missing history does not prove a MailKit delivery defect. Terminal body-unavailable records clear the pending diagnostic.
- Bound rich activity by both event count and encoded bytes, retaining counters and startup identity when evicting older events.
- Preserve the three-attempt, 20-second attempt and 60-second total deadlines. A cancelled or late request cannot commit a Junk intent.

Ordinary diagnostic records contain no subjects, addresses, bodies or raw model text. Explicit user-selected email reports and developer experiments remain private, separate exports.

## Deterministic failure tests

`./MacApp/test.sh` compiles `MacApp/Tests/FailureInjectionChecks.swift`. It injects a scripted transport into the production model adapter and a temporary store into NativeClassifier. Request planning, parsing, retry policy, scheduler and final protection gate are real application code. No actual model, Mail automation or MailKit move is invoked. Test-only scripts and accelerated deadlines are not shipped settings.

The suite passed **55 production assertions across 28 isolated scenarios** and **61 Dev assertions across 33 scenarios**. It checks the following conditions, plus the Dev-only cases described below:

| Condition | Required result |
|---|---|
| Empty, blank or malformed first response | Identified separately; valid retry can recover. |
| Three empty or malformed responses | Stop, retain mail, reserve no protection, suppress duplicate restart. |
| Refusal, unsupported language, valid negative or rejected evidence | Terminal; do not retry to force a positive. |
| Context overflow or temporary generation failure | Bounded retry; section limits actually reduce. |
| Incomplete multi-section analysis | Never report a completed negative or request Junk. |
| Uncooperative request past attempt deadline | Next attempt proceeds; a late positive has no action side effect. |
| Overall deadline or parent cancellation | Return without an action; discard all later results. |
| Pause, revision change or new protection during inference | Final action gate prevents Junk. |
| Burst, duplicate and queue overflow | Serialize accepted work, suppress duplicates, leave overflow untouched. |
| Empty keyword list | Allow a valid AI positive, while retaining negative/error, Preview, self-mail, account and recovery guards. |

Existing native tests additionally cover MIME extraction, body-request tracking, migration, corruption, error privacy, scheduler limits, deadline behavior and packaging boundaries. Swift 6 CLI tests cover options, parsing and persistent recovery independently. These simulations establish application behavior for injected conditions; they cannot establish Apple's inference implementation or guarantee Mail delivers callbacks.

## Separate feature and UI checks

An empty/comment-only keyword list saves, reloads and survives automatic standard-list upgrades. It disables only secondary keyword validation. The settings UI explains this behavior. Restore defaults restores both bundled text fields and requires Save Settings to apply; it does not modify account choices or recovery records.

The signed Dev app was staged at `~/Applications/Mail-Filter Dev.app`, with `org.mail-filter.development`, its own extension identifier and `group.org.mail-filter.development.shared`. The installed `/Applications/Mail-Filter.app` has an App Store receipt and remains build 18. The Dev app opened with no production accounts, displayed version 2.1.1 build 24 and restored both edited fields correctly. No production setup was changed and no Dev extension was enabled during this UI check. A later fictional Dev setup attempt could not be verified after computer-control access to the Dev app failed; it is not counted as a completed UI or email-file qualification.

Build 25 adds **Filter mail from my own addresses (testing)** only under `MAIL_FILTER_DEV`, off by default. Save Settings applies it with a new revision. Dev tests cover self-mail from selected and unchecked own accounts, positive/negative labels, Preview, keyword rejection, recipient/body/pause checks, restored-message protection and an in-flight opt-out. Production tests inject the same true JSON key and verify it is ignored and removed on encoding; production self-mail never reaches generation. A binary check also found the testing label/key in the signed Dev payload and absent from the unsigned Store payload. No test invokes a real Mail move.

## Real model reproduction experiments

The developer probe additionally ran **48 real-model trials**: six fictional short, long, forwarded, dense-link and issue-advocacy messages, two repetitions, and four policy/budget combinations. The baseline uses the exact previous standard policy digest, the original 6,000-character/64-token limits and the approved label parser. Comparisons independently change section size, output budget, and the candidate policy. All 48 returned the expected labels; none failed either parser. Recorded completed sections used at most 3,206 input tokens, seven output tokens and zero reasoning tokens; maximum per-section elapsed time was 4,827 ms. This does not reproduce the second Mac's failures.

A separate **16-trial output-limit control** used a fictional receipt and campaign appeal with caps of 1, 2, 4, 8, 16, 32, 64 and 256 tokens. The receipt produced incomplete labels `not` and `not-` at caps 1 and 2, which the application rejected. Caps 4 and higher returned valid negatives; all campaign trials returned valid positives. This reproduces real framework truncation only under deliberately tiny budgets. It does not explain a failure at the shipped 64-token budget and does not satisfy the review gate.

A read-only capability query on the local 64 GiB Mac reported a 4,096-token context and no reasoning capability. Do not infer the affected Mac's model capabilities or memory pressure from this result. Its exact input, raw reply/scalars, request usage and runtime conditions are still needed for a matching reproduction. Do not manufacture memory pressure on the working Mac or turn off production filtering to make an artificial failure look representative.

The private results are Desktop JSON exports named Mail-Filter Request Budget Comparison, Mail-Filter Baseline Stress and Mail-Filter Output Limit Controls. They are deliberately excluded from source control. Re-run the documented probes with an explicitly selected affected-email report rather than sweeping unrelated Desktop files.

## Release gates

Before any replacement review submission, recreate a plausible matching failure under the original contract, retain its input and numeric/raw selected-response evidence, and demonstrate the proposed mitigation against that same case plus negative controls. Injected empty replies, shortened test deadlines and tiny output caps establish application contracts, not the cause of this reported failure. If local synthetic cases continue to pass, obtain the affected Mac's selected-email export and a read-only baseline comparison rather than claiming the issue is fixed.

Also require the full native suite, Swift package tests, signed Dev verification, signed Store archive and exported-package verification. Regenerate the engineering Word guides, inspect their rendered pages and review the final diff for private data. Preserve approved, cancelled and delivered artifacts. A changed future Store binary needs a new build number; update its reviewer ZIP, notes and selected build together only after qualification and publisher authorization.

The signed Dev build-25 UI showed the self-mail switch off on upgrade, saved its enabled state and retained it after quitting and reopening the app. The only configured Dev address was fictional and Preview remained on; its extension remained disabled. Opening Activity then caused the computer-control helper to close its pipe, while the Dev app remained running. The exact reviewer email-file UI check therefore remains incomplete and is not counted as passed. Do not enable a working-inbox Dev extension or move real mail as an unattended test. No local pass establishes Mail action delivery or App Review approval. Timeout limits remain unchanged, and the Store submission remains on hold.
