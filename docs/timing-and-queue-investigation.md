# Timing and queue investigation

Current release decision (October 28): after reviewing the completed defensive audit and clean Store/Dev qualification, the publisher explicitly approved submitting build 27. The exact invalid-response cause remains unreproduced. Earlier hold statements below record the investigation at that time; see [current release qualification](release-2.1.1.md).

This October 28, 2026 investigation tests whether the native queue, cancellation and retry architecture can compound model failures on the publisher’s Mac. Candidate build 26 fixes two confirmed implementation gaps and improves queued cancellation. A real-model experiment also recreates the historical unbudgeted context overflow. The specific invalid-label/empty-response mechanism reported on the remote Mac remains unresolved; Store review remains on hold.

## Confirmed findings

The message queue serializes logical analysis jobs. Before build 26 it did not retain ownership of an SDK call after the job timed out. If a call ignored cancellation, the retry or a later queued message could enter another SDK call before the first returned. A native-pipeline test reproduced two simultaneous unreturned calls. This is a real architectural vulnerability under an injected uncooperative SDK, not evidence that Apple’s actual model behaved that way in the retained remote report.

The initial full-duration test also failed its overall-deadline check: a 60-second budget returned at approximately 63.008 seconds. The prior implementation used a utility-queue `asyncAfter`, whose timer scheduling permits leeway. The corrected implementation uses a strict one-shot Dispatch source with 10 ms requested leeway. The unchanged 60-second budget then returned at 60.023 seconds in qualification. Timer delivery remains best effort; this is not a hard real-time guarantee. [Apple’s timer scheduling documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcetimer)

The remote report’s two recorded jobs were not a queued burst: the first finished about ten seconds before the second started. Both first-attempt failures occurred after roughly five to six seconds, before the application’s attempt deadline. Queue-driven timeout overlap therefore is not established as their cause. Older/unrecorded calls, other processes and different request contents cannot be reconstructed from that report.

## Changes in candidate build 26

`Engine.system` always applies a shared process-local `ModelExecutionGate` around generation and token counting. A logical timeout or parent cancellation does not release that SDK slot until the awaited framework operation returns. Waiting callers can be canceled under their own existing deadlines; they leave without invoking the SDK. Ownership handoff is FIFO. If a callback returns after its deadline, the existing cancellation/action checks discard the result. There is no arbitrary cooldown or increased timeout.

`InspectionScheduler` now removes canceled waiting jobs promptly and never starts their operations. Its existing capacity and fingerprint/protection semantics are retained. Previously a canceled queued job waited until the active job returned before it could leave the queue.

`AnalysisDeadline` now uses the stricter one-shot timer described above. Three attempts, the 20-second whole-attempt limit, the 60-second overall limit and one-/two-second backoff remain unchanged. A test-only NativeClassifier seam permits historical section/output budgets; no end-user setting disables the production SDK gate or changes these deadlines.

The execution gate is not a machine-wide broker. Store, Dev, the UI host and CLI processes have independent memory. They can still call the system service at the same time. Nor does the framework returning from an await prove its underlying physical inference has stopped. If an SDK call never returns, the gate deliberately cannot declare the slot idle. Other jobs time out without starting overlapping SDK calls; recovery from that condition needs explicit health reporting and a qualified restart/recovery policy, not fabricated successful cancellation.

## Production-duration timing qualification

`./MacApp/qualify-timing.sh --full --output NEW_REPORT.json` uses disposable NativeClassifier stores, the production planner/parser/retry/scheduler/final gate, actual 20-/60-second deadlines and actual 1-/2-second retry delays. Scripted SDK operations deliberately ignore cancellation. No real model or Mail call occurs. It retains each scenario as it finishes, with a monotonic event timeline, temporary native activity and explicit assertions. The initial failed report is preserved alongside the corrected run.

| Scenario | Observed result |
|---|---|
| Former ungated behavior: first SDK call lasts 23 seconds, attempt expires, retry and queued peer proceed | Peak two unreturned calls reproduced; all late positives discarded. |
| Same scenario using the execution gate | Peak one unreturned call; retry waits for actual return; queued peer drains. |
| SDK negative returns after 19 seconds | Accepted before the 20-second deadline; one call. |
| SDK positive returns after 20.5 seconds | Expired positive discarded; retry produces a negative; no Junk intent. |
| Four-section negative, six seconds per generation, smaller retry sections | All three attempts share the total budget. First job returns at 60.023 seconds without falsely reporting complete coverage; queued peer completes at 67.124 seconds measured from the original submission. |
| Queued-job and model-slot waiter canceled while active work is held | Both leave promptly; canceled operations never start; active ownership remains intact. |

The 67-second scenario duration includes the next message’s processing and is not an extension of the first message’s deadline. This slow negative exposes a continuing tradeoff: several individually successful requests can exceed a whole-attempt budget, and restarting with smaller sections can repeat work. The current policy safely retains the message; it does not guarantee that every such message is eventually classified.

The normal native test suite includes accelerated versions plus **205 model-slot assertions**, including **200 cancellation-versus-handoff races**, FIFO/error recovery, and token-count isolation. Accelerated boundary margins are intentionally wider relative to filesystem overhead; only the full run qualifies the actual production durations. These finite scenarios are not an exhaustive proof of every OS scheduling interleaving or MailKit lifecycle.

## Real model context and queue experiment

`./MacApp/probe-model-queue.sh NEW_DIRECTORY` reconstructs the pre-splitting JSON request text from commit `00b9e1c` as data. It uses a fictional receipt containing dense tracking links, the historical standard rules and current local model assets. This is a constructed reproduction of the historical mechanism, not the lost original email or old model asset revision.

The unbudgeted request used **783 instruction tokens plus 3,808 prompt tokens: 4,591 tokens against a 4,096-token context**. The actual Foundation Models call returned `modelContextLimit`. This reproduces the class of explicit overflow recorded on this same host on October 12 and explains why the old identical-payload retry could not repair it.

The experiment then uses token-budgeted native processing under fixed historical rules, 6,000/3,000/1,500 maximum section characters and a 64-token output cap. Four blocks counterbalance burst versus paced order: burst, paced, paced, burst. Each block contains four fictional receipt/campaign messages, for **16 message trials and 24 real generation calls**. All expected outcomes passed. In the initial run, burst blocks took approximately 30 seconds; paced blocks approximately 33 seconds including intentional one-second gaps between messages. Completed generations used at most 3,189 input tokens, seven output tokens and zero reasoning tokens; maximum recorded request duration was 4,979 ms. No invalid/empty response or timeout was observed in those blocks.

A final repeat with the corrected timer also passed. A further **16-message / 24-generation run** used requested **ten-second idle gaps** between completed messages, matching the observed spacing between the two remote jobs more closely. All expected labels passed again, with no invalid/empty reply or timeout. Burst blocks took about 30 seconds; paced blocks about 63 seconds including the pauses. Its maximum request duration was 5,014 ms and reasoning usage remained zero. Model-probe runs did not overlap: saved request/result timestamps establish that the previous run completed before the next began. These are functional observations on the working Mac, not a calibrated idle-machine performance benchmark. The runner now defaults to ten-second gaps and accepts an optional gap argument from one through 60 seconds.

This establishes that budgeted processing can handle this constructed content, and that queued bursts alone did not trigger the reported invalid-label symptom in these trials. The experiment changed the historical JSON interface to the released String contract as part of the recorded migration; it is not a single-variable proof that splitting alone repairs every generation failure. It does not emulate the remote hardware or establish its selected model variant.

## Mail download and callback architecture

The callback thread returns after creating asynchronous work, but the body-ready MailKit completion handler remains pending until queue admission, classification and final checks finish. Apple documents completion-based action decisions; it does not provide a download-independence guarantee in that contract. [MailKit action decisions](https://developer.apple.com/documentation/mailkit/memessageactionhandler/decideaction(for:completionhandler:))

There is one active logical job plus 16 waiters. Queue residence is outside the 60-second analysis budget, so a saturated queue can retain a completion much longer than 60 seconds. Queue overflow leaves mail untouched. There is no persistent retry queue or guaranteed replay after a callback is completed. Releasing a callback with nil and assuming a later MailKit Junk action is possible would not be a sound redesign; any delayed-action mechanism must first be demonstrated within the Store-supported API/entitlement boundary.

These experiments did not send mail, alter Mail accounts, enable extensions, move mail, replace an installed app or change its settings. They do not qualify live Mail download behavior. Synthetic intended-Junk counters are only in disposable stores, and unified test logs are distinguished by their test process names.

## Remaining architecture work and release decision

1. Capture an actual invalid/empty String response with exact request, usage and transcript evidence. The historical JSON parse failure and the remote whole-label failure remain different contracts; their shared cause is not yet established.
2. Evaluate retained section progress or a per-generation deadline within a bounded message budget, so reducing sections does not unnecessarily restart completed negative work. Preserve exact immutable message/policy provenance and all final recovery guards. Test this as a separate change rather than merely doubling timeouts.
3. Add explicit model-slot health and queue-wait reporting, including the distinction between a caller returning and the SDK returning. Qualify a circuit/recovery policy for a never-returning call without launching overlapping work or killing the system model service.
4. Measure real MailKit callback duration, body-ready arrivals and download progress locally with the isolated Dev extension in Preview. Establish acceptable backlog/overflow behavior before selecting a queue-age limit or durable work design. A separate macOS user isolates settings, not the model service or physical resources.
5. Decide whether cross-process exclusion is necessary and supportable through the provisioned shared container. A gate in one process does not coordinate the installed Store app, Dev app and independent CLI.

The signed Dev build-26 payload and its provisioned capabilities passed verification; it was built without installation or extension activation. The unsigned Store archive and payload exclusion checks also passed. Native regressions, the 29 CLI tests and rendered engineering Word checks passed.

Candidate build 26 is engineering work, not a replacement Store submission. The original invalid-label reproduction requirement remains open. The publisher should review these concrete findings before any review-gate change; successful controls and timeout-safety fixes do not silently waive it.

## Private evidence locations

Ignored outputs under `.build/model-replays/` retain the initial failing timing report, its source checkpoint, the corrected full-duration report, and the actual-model queue experiment’s fictional requests, replies, native activity and historical contract. Reports are private engineering artifacts and are not committed. The public repository retains code and this numerical summary only.
