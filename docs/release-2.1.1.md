# Mail Filter 2.1.1 release qualification

Candidate build 27 completes a defensive-programming and diagnostic audit following the original invalid-response investigation. The exact reported first-attempt failure remains unreproduced. This document records the candidate and evidence; it does not claim that a successful control or an injected timeout establishes that cause. The publisher explicitly approved submitting this qualified candidate. Transporter delivery and Apple processing succeeded. App Store Connect confirmed version 2.1.1 is Waiting for Review with build 27 submitted.

## Defensive audit

The candidate retains the supported String classification interface, token counting and output/framing reserves, overlapping section coverage, bounded three-attempt retries, 20-second whole-attempt and 60-second total limits, source verification, settings-revision checks and persistent restored-message protection. Build 26 added process-local SDK ownership through cancellation and a stricter deadline timer. Build 27 does not add arbitrary cooldowns, increase deadlines or introduce unqualified URL rewriting.

Ordinary records now distinguish logical queue wait, completed model-slot wait and model-slot ownership at attempt failures. Request IDs, exact instruction/prompt SHA-256 fingerprints, model variant and reasoning capability accompany request metrics. Current hardware/model metadata in exported diagnostics is labeled as current rather than evidence of an earlier environment.

A separate private failure cache retains original rejected output even after retry recovery. It holds at most 32 records and 512 KiB, with up to 8 KiB of exact reply bytes per record and a full-reply digest. Seven-day export eligibility and write-time pruning bound retention. It contains policy revision and request measurements, but no separately saved email source or original prompt. The fingerprints detect changed inputs; they cannot reconstruct an earlier custom policy. Ordinary activity and application reports exclude these replies. Only an explicit matching-email export includes them, with a privacy notice. A failed cache write cannot change the classification/action outcome. Tests cover corruption recovery, count/byte/age limits, invisible characters, same-message export scoping and removal.

## Qualification evidence

- Full-duration timing: all six scenarios passed using actual 20-/60-second deadlines and 1-/2-second backoff. Former ungated overlap reached two outstanding SDK calls; the guarded case stayed at one. Late positives were discarded. Slow incomplete negatives were retained rather than declared successfully negative.
- Native suite: passed, including 115 settings/storage checks, 66 production assertions across 29 injected scenarios, 72 Dev assertions across 34 scenarios, 206 model-slot checks and accelerated timing. All existing MIME, routing, protection, retry, replay, build-graph and diagnostic checks passed.
- CLI suite: all 29 Swift tests passed.
- Actual model: all 16 fictional messages in four queued/paced blocks passed under the candidate's bundled policy and 256-token output reserve, using 24 generation calls. Maximum recorded input was 3,085 tokens, output seven tokens and generation 4,896 ms; no invalid/empty reply or timeout occurred. These successful controls do not reproduce the reported failure.
- Clean signed Development build and clean signed Store archive: both passed signature, matching host/extension version/build and provisioned-group checks from separate new derived-data directories. The exported App Store package passed installer, distribution-signature, profile and payload verification. Refreshed build-27 fictional reviewer samples were packaged separately.
- The clean Dev app was staged at `~/Applications/Mail-Filter Dev.app` and displayed 2.1.1 build 27, fictional reviewer account and saved Preview. No extension was enabled. Computer control disconnected upon entering Activity, as in the earlier build-25 UI attempt; the Dev process remained running and no matching new app crash report was found. The signed Activity/email-file GUI test is therefore incomplete, rather than counted as passed.
- Registered Word documents match Markdown. Changed rendered guide pages were visually checked. Final source diff and package metadata were reviewed for private data.

All automated cases use fictional messages or scripted transports and disposable stores. They never access Mail or request real moves. The installed Store app remains approved build 18; Dev was updated separately to clean build 27, with prior Dev app preserved. No production settings or filtering-extension activation was changed.

## Known limits

The gate coordinates one process, not every app on the Mac. An awaited SDK call returning does not prove internal Apple-service cleanup has completed. A never-returning call holds the gate while other callers expire safely; the app does not kill system services or fabricate cancellation completion. Multi-section negatives can exhaust the whole-message budget, and sectioning cannot preserve every long-distance inference. MailKit callback delivery and actual mailbox movement are outside the inference tests; counters record requested actions, not confirmed moves. These limits remain explicit rather than being presented as resolved defects.

## Clean build requirements

Use separate new derived-data directories for Development and Store, with the same source tree, version 2.1.1 and build 27. Verify host and embedded extension build numbers, signatures and provisioned groups in each. The development identity must remain `org.mail-filter.development` with its isolated group; the Store identity must remain `org.mail-filter.app`. Preserve previous archives/packages, verify the exported Store package and refresh reviewer notes/samples to match the selected build. No installation or extension activation is part of archive/export.

## Prepared artifacts and current status

The Store upload package is `outputs/store/Mail-Filter-2.1.1-build-27.pkg`; the isolated Dev ZIP is `outputs/development/build-27-clean/Mail-Filter-Dev-2.1.1-build-27.zip`. Matching fictional reviewer samples are `outputs/store/Mail-Filter-Review-Samples-2.1.1-build-27.zip`. A private output manifest records package/sample digests and both bundle identities. Previous build-24 archive/export and earlier submitted packages were preserved.

The publisher signed in and explicitly answered “Submit build 27” to the candidate-specific confirmation, superseding the earlier reproduction-only hold. Transporter delivery succeeded. Build-27 release notes, reviewer instructions, entitlement explanation and fictional sample ZIP were saved in App Store Connect. After processing, build 27 was selected and saved, then added and submitted for review. App Store Connect confirmed Waiting for Review and 1 Item Submitted. This report does not represent the original failure as resolved.

## Dev installer isolation follow-up

The October 29 packaging follow-up fixes a stale generic direct installer that could replace the Store app. Default packaging and the new **Mail-Filter Dev Installer** Xcode scheme now produce **Mail-Filter Dev Installer.pkg**, installing **/Applications/Mail-Filter Dev.app**. Store remains **/Applications/Mail-Filter.app**. The legacy direct package has an explicit Direct filename and refuses Store receipts, Store metadata, unexpected identities and redirected destinations. The original submitted Store build 27 is unchanged.

Dev packaging preserves the signed app/extension, uses distinct installer and optional CLI PATH identities, and leaves both App Groups intact. The exact marketing version and build appear in the installer title, introduction and conclusion; the native Installer introduction was checked for **2.1.1 (build 27)**. Both Dev and legacy direct package builds and expansion/signature verification passed. Temporary-volume regressions cover destination collisions, Store receipts, stale processes, independent PATH entries, old shortcut retirement and unrelated Desktop content. Neither package was installed by these qualification tests, and no real email was read or moved.

The developer guides and generated Word copies describe the new workflow. Mail owns the independent extension checkboxes; the public MailKit manager has no API to enforce mutual exclusion. Users must disable one extension before enabling the other. No new filtering, model or cross-group coordination behavior is introduced by this packaging change.
