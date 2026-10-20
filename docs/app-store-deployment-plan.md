# Mail Filter App Store Deployment Plan

Mail-Filter can retain its current MailKit and on-device classification architecture for a Mac App Store edition. The recommended approach is one shared code base with separate build configurations for local engineering, sandboxed development, and Store distribution. Support logging should remain available in the Store edition. Different builds are needed for signing, capabilities, development tools and installation behavior, rather than to make log files possible.

Desktop probes confirm that App Sandbox permits our synthetic model classification, private file logging and settings storage. A Mail-targeted Apple Events exception also permits the account-count query; compose-only permission fails that query. Use the targeted exception as the candidate for signed qualification of account setup and selected-email diagnostics. Provide an address-based setup and email-file analysis fallback if automation is unavailable or unacceptable to App Review. A successful runtime test does not guarantee entitlement acceptance or App Store approval.

Assessment date: October 17, 2026. Baseline: build 13, commit `2cee33b`. The checks used an Apple silicon Mac with macOS 27.0.1, Xcode 27.0 and SDK 27.0. This plan records completed checks separately from the desktop, provisioning and review gates that remain open.

Qualification update, October 19, 2026: developer-team access is active. Build 15 passed signed Development startup, account discovery, settings persistence, read-only analysis, shared activity, incoming Preview and actual Junk moves. A restored message stayed in Inbox after Mail restarted, and the user confirmed a Junk move with the settings app closed. The production archive and local distribution export passed their signature, provisioning and payload checks. Build 18 subsequently processed in App Store Connect, and the publisher reported completing submission for App Review. Section 10 separates these observations from the remaining clean-install tests and review outcome. The original installed app is preserved; the separately identified development extension is the active test installation.

## 1 Feasibility findings

Apple explicitly supports distributing MailKit extensions through the Mac App Store. Our incoming handler already obtains message data and requests Junk actions through that public API. The settings application, packaging and supporting diagnostics require the larger changes. See [Apple MailKit presentation](https://developer.apple.com/videos/play/wwdc2021/10168/) and [App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

At the build-13 assessment baseline, the native settings application was unsandboxed and its embedded extension used a narrow local-development filesystem exception. The direct Local and DeveloperID configurations retain that intended host behavior. The root Xcode project additionally provides sandboxed Development and Store configurations with shared-group entitlements. The following tables describe the October 17 probes; Section 10 records the subsequent signed Development qualification.

| Check | Result | Evidence and limit |
|---|---|---|
| Existing regression suite | Passed | All named checks in `MacApp/test.sh` passed, including recovery, retries, MIME, settings and diagnostics. |
| Offline Store scenarios | Passed | Ten additional checks cover address-based routing, email-source decoding, migration and private activity. |
| Probe compilation and signatures | Passed | Four isolated app bundles compile and their ad-hoc signatures and entitlement dictionaries verify. |
| Container logging and storage | Passed in desktop probes | All four variants round-trip synthetic settings, activity and an owner-only log file. Logger calls complete and the current-process log store opens. |
| Basic sandbox process | Passed in desktop probes | All three sandboxed variants exit successfully and report a containerized home directory. |
| Sandboxed Mail automation | Partial desktop evidence | The Mail-targeted exception reads account and selection counts. Compose-only metadata access fails with privilege error -10004. No selected-message source was tested. |
| Synthetic model generation | Passed in desktop probes | All four variants classify the synthetic campaign appeal as political using the shared model code. |
| Provisioned App Group | Not established by the October 17 probes | These ad-hoc experiments did not use team-authorized profiles. Later signed sharing results are in Section 10. |

The user ran the complete matrix from a normal Terminal session on October 17, 2026. All four variants completed with exit code zero, verified signatures and matching entitlement dictionaries. The three sandboxed variants confirmed containerized storage. Their observed differences were limited to Mail automation in this run:

| Variant | Mail preflight | Read-only metadata result |
|---|---|---|
| Baseline without sandbox | 0 | Account and selection counts read successfully. |
| Sandbox without Mail entitlement | -600 | No metadata query attempted after unsuccessful preflight. |
| Sandbox with compose group | 0 | Metadata script rejected with -10004, an Apple Events privilege error. |
| Sandbox with Mail-targeted exception | 0 | Account and selection counts read successfully. |

Mail was visible as running to every variant. No message was selected, so the successful metadata queries did not exercise the selected-source branch. Preflight success alone does not prove that a particular Apple Event is allowed, as the compose result demonstrates. The plain sandbox's -600 is `procNotFound` in the SDK; it does not mean Mail was closed, and this run did not isolate its cause.

Earlier attempts inside the restricted execution environment could not launch the sandbox helper or complete synthetic generation, and did not see Mail. The successful desktop run establishes that those outcomes are not reproducible in the normal session. It does not identify their precise cause. These probes alone did not establish provisioned sharing, selected-message source access, permission denial or Store archive behavior; subsequent qualification is recorded separately.

The desktop run used `--all-runtime --mail-metadata --synthetic-model`, without requesting new Mail permission. The probes did not install or enable a Mail extension, access production filter settings, move messages, send mail, or change the working installation.

### 1.1 Findings from the source and SDK audit

`AccountInventory.swift` uses Apple Events to read Mail account names, identifiers and addresses. `MessageDiagnostics.swift` uses Apple Events to obtain the selected message and its source. The installed Mail scripting dictionary exposes a compose access group, but does not mark these account-reading and received-message properties as members of that group. The desktop privilege error confirms that compose permission is insufficient for the tested metadata script. The target-specific exception succeeded for counts; the full account inventory and selected-source operations still require qualification. Apple's documented exception mechanism also requires an entitlement justification for review. See [Apple Events exceptions](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html).

The current MailKit message header exposes sender, recipients, headers and raw source, but does not provide the account inventory used by our settings UI. Manually supplied address groups already fit `FilteringConfiguration` and preserve cross-account own-sender protection in the offline checks. This proves reuse of the routing contract; it does not implement the replacement UI or solve every alias and Bcc ambiguity.

The initial policy-and-protection importer left UI account selection and pause state unreconciled. Build 14 adds a complete versioned setup archive that preserves inventory, aliases, selection, pause and preview. Imported recovery digests commit atomically with settings, destination recovery is retained, and the final action gate requires explicit import confirmation. Synthetic checks establish these contracts; signed file access and the complete transition UI still require qualification.

The system-log collector launches `/usr/bin/log`. It should not be the Store edition's essential support mechanism. The shared activity file already provides structured events from the extension without reading a system-wide archive. Sandbox-compatible logging is an implementation and privacy concern, not a reason to maintain two filtering engines.

### 1.2 Reproducing the checks

Run from the repository root with Xcode selected:

```sh
./MacApp/test.sh
python3 MacApp/Feasibility/run.py --offline-only
python3 MacApp/Feasibility/run.py --all-runtime \
  --mail-metadata --synthetic-model
```

The matrix builds a baseline, a plain sandbox, a compose-group sandbox and a Mail-targeted sandbox. Results are written to `.build/app-store-feasibility/results.json`; binaries and reports are ignored by Git. The default metadata check preflights permission without asking for consent. It queries counts and selected-message source length only when already authorized. It never prints source text or account addresses.

From a normal Terminal session, `--all-runtime` attempts every variant even if basic sandbox startup fails. `--request-mail-permission` permits macOS to ask for consent and implies the metadata test. Read each consent prompt before allowing it. These ad-hoc probes remain preliminary; repeat the accepted scenarios in the signed qualification application. The harness is documented in `MacApp/Feasibility/README.md`.

## 2 Developer requirements

### 2.1 Membership and publisher identity

App Store publishing requires Apple Developer Program membership, currently USD 99 per membership year in the United States. This applies to free apps as well as paid apps. A free account remains useful for development but does not provide App Store distribution. Eligible nonprofits, accredited educational institutions and government entities can request a fee waiver. Enrollment and any payment are decisions for the account holder. [Apple enrollment requirements](https://developer.apple.com/programs/enroll/)

An individual enrollment publishes under the person's legal seller name. An organization enrollment requires an eligible legal entity, binding authority, organizational contact information and generally a D-U-N-S number. Decide the publisher identity before registering production identifiers and releasing data-bearing installations. The account uses an Apple Account with two-factor authentication.

### 2.2 Tools and signing assets

Keep the current development requirements: Apple silicon, supported macOS, full Xcode with first-launch setup complete, Python 3 for generated documents, and Git. Use an Apple Intelligence-capable test Mac with the model downloaded and enabled. At least one additional Mac or isolated user account is needed for installation and migration qualification.

After enrollment, configure Apple Development signing for sandboxed engineering builds and appropriate App Store distribution signing and provisioning for uploads. Register the host and extension identifiers and authorize their shared App Group. Let Xcode manage profiles where practical, then verify the resulting signed entitlements and embedded profiles. Developer ID certificates belong to the optional direct-download channel, which remains a separate packaging choice. [Apple certificate types](https://developer.apple.com/help/account/certificates/certificates-overview/)

The developer needs App Store Connect access with appropriate roles. Keep signing keys and upload credentials in Keychain or the chosen secure CI secret store. Never commit profiles containing personal information, private keys, passwords or API credentials. Retain reproducible archives and symbols for each released build.

### 2.3 Store and business preparation

Create an app record, check name availability, accept the applicable agreements and select territories. Prepare screenshots, description, support contact, privacy policy, age-rating and export-compliance answers. A paid app or in-app purchases also require the Paid Apps Agreement and banking/tax details. These decisions are independent of the engineering choice to preserve the CLI. [App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow)

Declare EU trader status as required in App Store Connect. Trader contact details are displayed for qualifying EU distribution, which should be considered when selecting publisher contact information. [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)

## 3 Build configurations and distribution

Debug versus Release controls optimization and engineering behavior. Distribution controls identity, provisioning, capabilities and payload. Treat these as separate dimensions in the project. TestFlight should exercise the same Store capabilities and release payload intended for publication.

| Configuration | Intended use | Identity and capabilities |
|---|---|---|
| Local engineering | CLI work and synthetic checks | Existing local build remains available; its unsandboxed host is not evidence of Store compatibility. |
| Sandboxed development | Debugging Store behavior | Development identity, isolated development bundle IDs and App Group; host and extension sandboxed. |
| Store Release | TestFlight and public Store | Production identifiers, provisioned group, release signing and identical feature restrictions for both channels. |
| Direct Release optional | Distribution outside the Store | Developer ID and notarization; retain only if there is an ongoing need for the current installer and CLI option. |

One implementation of decoding, routing, inference, verification, retries and recovery should serve all configurations. Keep shared Swift sources and targeted capability adapters. Avoid copying the classification engine or using a separate prompt merely to make a Store build pass tests.

The Store product should contain one settings application with its MailKit extension. Exclude the sibling uninstaller, system PATH components, Desktop shortcut creation and bundled engineering CLI from that payload. Keep the standalone CLI, synthetic fixtures and engineering scripts in the repository and any separately distributed developer tools. Store updates should follow the Store workflow. [Mac App Store rules](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)

Use a clearly different display name and bundle identifiers for development copies. Keep development settings, logs and protection isolated from production. Never enable development and production filtering extensions simultaneously against the same real inbox during qualification. On an isolated test installation, migrate protection before allowing any apply-mode processing.

Release checks must reject development filesystem exceptions, unintended automation or network entitlements, debugging permission, engineering binaries, personal configuration and private email fixtures. Distinct output paths should prevent a local installer or ad-hoc bundle from being mistaken for a Store archive.

## 4 Logging and diagnostics

### 4.1 Logs in both development and Store builds

Keep useful diagnostics in the Store product. Apple's Logger API and files inside authorized containers provide suitable mechanisms. Debug builds can add detail while Store builds retain a bounded record of callbacks, queueing, model outcomes, evidence rejection, retries and action requests. Preserve the distinction between a Junk request and a confirmed mailbox move. [Apple Logger documentation](https://developer.apple.com/documentation/os/logger)

Every desktop variant completed Logger calls, opened an `OSLogStore` restricted to its current process, and round-tripped a private synthetic log file. This includes all three sandboxed variants. The probes did not demonstrate cross-process log retrieval, archive retention or provisioned App Group writes. Signed qualification must test host/extension sharing and report export. The implementation can rely on shared structured records rather than system-wide log access. [Current-process log scope](https://developer.apple.com/documentation/oslog/oslogstore/scope/currentprocessidentifier)

### 4.2 Proposed support record

Use one typed diagnostic schema across the host and extension. Include build/channel, timestamp, event category, opaque message key, attempt count and sanitized error domain/code. Do not automatically record subjects, addresses, bodies, evidence quotes or raw model requests. A hashed identity is still potentially linkable diagnostic data and should not be described as anonymous.

Continue using the bounded shared activity store. If longer file history is needed, add rotating JSON-lines logs in the App Group: proposed limits are three files of up to one MiB each, plus an age limit of seven days. Serialize rotation across processes, use owner-only file permissions, and tolerate unavailable or full log storage without permitting an unsafe action. Recovery protection must remain in a separate persistent store and must not expire with diagnostic retention.

The host should export a support report from these shared records through a Save panel. Detailed email export remains a distinct user action with a clear notice that the file includes private source and filtering instructions. There should be no background upload of either report. More verbose developer logging should be opt-in and should still exclude email content by default.

Replace the Store dependency on `/usr/bin/log` with these records. Console logging may remain useful during development, but successful system-archive collection must not be a prerequisite for diagnosing an incoming callback. Test unavailable log services, rotation, concurrent writers, full disk and exporting while filtering continues.

## 5 Mail automation decision

### 5.1 Qualification first

Use the Mail-targeted exception for the next signed qualification build. The desktop comparison establishes account-count access with this candidate, while compose-only access fails. Extend qualification to the actual account names, identifiers and addresses used by setup, plus selected-message source on explicit request. Keep permission preflight, user denial and timeout paths explicit. Request only the capability necessary for these features; never use broad filesystem access or UI scripting to substitute for supported Mail APIs.

A successful candidate must read account metadata, obtain the selected message source on explicit user request, survive denial, and work after app and Mail restarts. It must also work from the distributed archive rather than only when launched by the debugger. The provisioned App Group and the embedded extension must work without the local-development file exception.

Runtime success establishes feasibility. Upload validation establishes acceptance of the archive's technical structure. App Review establishes acceptance of the submitted use and entitlement justification. Record these as three different gates. If necessary, use Apple's technical support and App Review communications to resolve the entitlement question before relying on it for a public release.

### 5.2 Supported fallback

Implement a setup model with a complete list of the user's protected addresses and a selected subset to filter. The addresses must cover accounts and aliases that are not enabled for filtering, preserving cross-account own-sender protection. Normalize and validate them through the same shared configuration logic used today.

Provide user-opened `.eml` analysis and report export using the same MIME decoder, model interface and verifier. Imported files are analysis inputs and do not authorize mailbox actions. Ambiguous recipient/account mapping should be shown in the analysis UI rather than guessed. A manual configuration needs local stable identifiers and must not pretend those identifiers are Mail's account IDs.

Keep automatic discovery and direct selected-Mail analysis behind an explicit capability adapter. Retain them in the Store edition only if the signed tests and review permit them. The address/email-file path should remain usable when automation is denied, rather than leaving users unable to finish setup or report a failure.

## 6 Implementation work packages

### 6.1 Establish the account and signing foundation

Owner: account holder with engineering support. Paid-team access, the Apple Development identity and Development app/extension profiles are now established. Xcode registered the test Mac and authorized the Development App Group. Production identifiers, the separate production group and distribution assets must also qualify through archive/export. Keep team overrides in the ignored local configuration and establish certificate custody and App Store Connect roles.

### 6.2 Add a Store build pipeline

Implemented in build 15. The root `Mail-Filter.xcodeproj` owns the shared app and extension targets, plus separate engineering CLI and uninstaller targets. Its Local, DeveloperID, BuildCheck, Development and Store configurations select the channel's identity, storage, entitlements and signing. `MacApp/generate-project.py` is the native source-list authority; shell build entry points invoke the same project. The developer guide documents all five schemes and their Build/Run/Archive behavior.

The Local Installer scheme packages native dependencies without recursively compiling them. Store schemes and payload checks exclude engineering tools, the uninstaller, PATH components and Desktop shortcuts. A shared target regenerates the Word documentation for native builds. Configuration files live in `MacApp/Build/`; private team settings belong in the ignored `Signing.local.xcconfig`. Automatic archiving uses development signing; App Store export applies distribution signing. Archive verification is a separate stage and must never substitute for strict verification of the exported distribution artifact. See [Apple's distribution signing workflow](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/).

### 6.3 Complete shared storage and migration

Owner: engineering. Update `NativeStorage` and `SharedStore` to resolve the authorized group consistently in the host and extension. A missing group must stop processing rather than fall back to another build's data. Keep production identities and data locations stable after launch. Refer to [App Group access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Create an explicit export/import flow for settings and protection. A selected settings file does not automatically grant access to an adjacent protection file: request the containing export folder, both individual files, or use a single versioned migration archive. Add the required user-selected-file capabilities and use security-scoped access where needed. [User-selected file access](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)

Preserve policy, evidence terms, addresses, aliases, preview/apply choice, pause preference and protected identities. Reconcile UI selections by supported identity/address mapping. Require explicit confirmation before the new installation begins moving mail, while displaying the imported preference. Validate the complete import before replacing active settings; preserve source files and maintain a recoverable destination backup. Retain protection records independently of diagnostic logs.

Remove implicit reads of the CLI state and older containers from the Store save path. Make legacy recovery import an explicit user-selected operation. Test missing protection, corruption, older schemas, repeated import, a busy store, interrupted writes and a failed import after protection validation. Existing fixtures provide reusable coverage but do not prove Powerbox permissions or a complete migration UX.

### 6.4 Adapt setup and selected email analysis

Owner: engineering and product. Introduce the automation capability adapter in `AccountInventory` and `MessageDiagnostics`. Implement the address-based setup and email-file analysis path in `SettingsModel` and `SettingsView`. Preserve own-address protections, selected-address routing, explicit preview behavior and clear unsupported/denied states. Run the automation decision gate before settling the final Store feature set.

Keep the filtering engine in `NativeClassifier`, `PoliticalModel` and the shared helpers. Continue using the supported permissive string-response path and source-evidence verification. Apply no App Store-specific classification shortcuts. Explain model readiness and the first-6000-character limit consistently in the UI and support information.

### 6.5 Product diagnostics and privacy

Owner: engineering and publisher. Implement the logging design in section 4 and adapt `DiagnosticReport` to use shared records. Add accessible privacy/support links and the intended user-selected export capabilities. Inventory required-reason APIs and include the relevant `PrivacyInfo.xcprivacy` manifests in the correct bundles. The existing `systemUptime` calls need an approved reason matching their timer use; add no reasons for APIs the shipped product does not use. [Required-reason API guidance](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

Prepare accurate App Store privacy answers after auditing the final binary and any support or analytics services. Local inference alone is not off-device collection under Apple's definition. Evaluate optional reports and any future services separately. Review the Foundation Models acceptable-use requirements and keep the product a user-directed classification tool. [App privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Foundation Models acceptable use](https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework/)

### 6.6 Qualify behavior on real installations

Owner: engineering with volunteer testers. Use isolated accounts or explicitly designated test inboxes for mailbox-action tests. Obtain authorization before controlled message moves. Do not test a new signing or storage mode against the existing live configuration until migration and rollback are proven.

Test callback receipt, body retrieval, queue behavior, model completion, evidence decisions and Junk requests separately. Verify mailbox contents to establish actual moves. Restore a test false positive and confirm it stays in Inbox after callbacks, restarts and policy changes. Test the same cases after an update and settings migration.

Qualify the supported OS range and model availability/language states, alias/Bcc delivery, multiple providers, sleep/wake, Mail restarts, host quit, permission denial, burst arrival and unavailable storage. The Store listing must explain that filtering occurs on the Mac while Mail runs and the machine is awake. It should not promise perfect accuracy or remote processing while the Mac is unavailable.

### 6.7 Beta and submit

Owner: publisher and engineering. Distribute the release candidate through TestFlight, collect reproducible reports, fix launch/setup failures and confirm the migration path with another tester. A TestFlight build uses Store capabilities; it should not contain a special unsandboxed escape path. [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

Complete App Store Connect metadata and compliance answers. Include synthetic sample emails, instructions to enable Mail-Filter in Mail, Apple Intelligence requirements and a repeatable demonstration of classification and extension behavior. Supply a reviewer contact and explain any requested automation entitlement. Reviewers should not depend on naturally arriving political email to evaluate the product. [App Review preparation](https://developer.apple.com/app-store/review/)

Upload using Xcode or Transporter, choose the processed build, add it for review and submit. Use manual release for the first version so approval and publication are separate decisions. Resolve review feedback before release. Keep the accepted archive, symbols, entitlement report and release notes. [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

## 7 Required release gates

| Gate | Current state | Evidence required |
|---|---|---|
| Publisher and signing | Paid team, Development profiles and distribution export passed | Maintain signing assets and publisher access |
| Sandboxed desktop startup | Signed Development passed | Confirm startup from the final Store installation |
| Shared storage | Signed Development passed | Confirm the separate production group on a clean installation |
| Setup capability | Signed inventory and selected analysis passed | Qualify denial and manual paths; obtain entitlement acceptance |
| File selection and export | Fixture checks passed | Signed Open/Save panels and exports work without broad exceptions |
| Model execution | Signed incoming classification passed | Complete the provider, language and model-availability matrix |
| Migration and recovery | Fixtures and signed restoration passed | Complete signed setup import, confirmation and update migration |
| Store diagnostics | Shared activity passed in Development | Qualify signed support-file export, rotation and failure behavior |
| Mail actions | Junk, restoration and host-quit tests passed | Repeat relevant checks from the final Store installation |
| Store archive | Signed archive, local export and build 18 upload processing passed | Preserve the submitted archive and exported package |
| App Review | Publisher reported submission of version 2.1.0 build 18 | Apple accepts the submitted build and requested entitlements |

No gate should be marked passed solely because an ad-hoc signature verifies or the unsandboxed CLI works. Keep the archived build, signed entitlements, OS/Xcode versions and reproduction steps with each qualification result. Store actual test reports outside public documentation if they contain user data.

## 8 Immediate next actions

1. Monitor the submitted version in App Store Connect and respond to Apple's questions or requested changes. Submission is not App Review acceptance; the selected release setting is automatic release after approval.
2. Preserve the submitted build-18 package and archive. A development-signed archive alone is not a distributable Store artifact; the exported package has separately passed distribution checks.
3. Complete signed file-panel, email-file, setup import/confirmation, denial, clean-install and update tests. Repeat the necessary runtime checks with production storage and a TestFlight or Store installation.
4. Complete the remaining provider/model matrix and keep the published support/privacy pages consistent with the app. Preserve the working developer CLI and original installation until migration is qualified.

## 9 Implementation completed before signed qualification

### 9.1 Build and capability separation

`Mail-Filter.xcodeproj` at the repository root builds the same host and embedded extension targets for every distribution channel. Its Development and Store configurations are sandboxed and use separate bundle IDs and groups; Local and DeveloperID retain direct-distribution behavior. The Store scheme excludes the separate engineering CLI, uninstaller and packaging targets. `MacApp/Build/` holds the shared configuration and signing templates, and `MacApp/generate-project.py` owns native source membership. `MacApp/store-build.sh check` creates an unsigned archive with development identities, exercising the Store configuration without colliding with the installed product's identity. Xcode records build products with Launch Services, so unsigned checking also uses the development identifiers.

The Store payload excludes the CLI, PATH scripts, uninstaller and Desktop shortcuts. The direct scripts and standalone CLI remain available. The Store compilation excludes the unified-log subprocess collector. A verifier checks bundle metadata, payload exclusions, manifests and declared capabilities; signed modes additionally check signed entitlements and embedded group profiles. The unsigned archive passed these applicable checks. It has not been launched or submitted.

### 9.2 Setup and migration

Manual address entry accepts one account group per line and comma-separated aliases. All entered groups protect own-sender mail, including groups not selected for filtering. IDs are explicitly local. Refreshing Mail account discovery preserves previously configured addresses missing from Mail's inventory. Selected-message diagnostics can match manual setup using recipient headers; email-file analysis reports the routing limitation and never authorizes a Mail action.

Export Setup creates one private JSON archive with settings and recovery digests. Import validates the entire archive, preserves pause/preview and UI inventory, merges existing protection, creates a private destination backup and atomically replaces settings with imported protection included. The source remains untouched. Confirm Imported Setup is required before filtering can resume; confirming retains the imported pause preference and invalidates older in-flight results. Missing or damaged protection in an explicitly selected legacy folder prevents migration.

The save path no longer reads legacy CLI state implicitly or searches older containers. Earlier inherited CLI protection remains in the saved policy. A user-selected folder or setup archive supplies explicit migration access. The original policy-only import helper remains for engineering compatibility; the settings UI uses the complete archive path.

### 9.3 Diagnostics and privacy

Open Email File analyzes a user-selected RFC message through the shared MIME decoder, model and verifier. Read-only files and Mail selections share report export, with complete private source included only on explicit request. Application support reports remain separate and can be saved through a file panel.

Shared settings and activity still use cross-process locking. Supplementary JSON-lines history rotates at one MiB per file, retains at most three files and reports events within seven days. Expired files are pruned on a subsequent write; recovery protection is independent. Failed log writes do not discard the successfully saved activity or authorize an action. Store diagnostics rely on these records rather than system-wide logs. Private record fields include build/channel when supplied by the bundle, event category, opaque key, attempt and sanitized error metadata.

Privacy manifests accompany both Store bundles. They declare elapsed-time measurement and file metadata access for authorized storage and user-selected files. The current reasons are `35F9.1`, `C617.1` and `3B52.1`; final binary and questionnaire review remains necessary. See [Apple required-reason API guidance](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

### 9.4 Verification and account dependent handoff

The native regression suite passes, including 42 dedicated checks for manual setup, complete migration, protection retention, import confirmation, email-file extraction, export privacy, log rotation, expiry and log-storage failure. All use synthetic input and temporary stores. The unsigned Store archive also passes payload inspection. These automated checks establish fixture contracts; signed runtime observations are recorded in Section 10 and do not replace clean-install or App Review qualification.

`MacApp/Store/README.md` contains the commands for signed development, production archiving and local export after enrollment. `docs/store-review-preparation.md` provides listing and entitlement notes plus a reproducible reviewer demonstration. The public pages and submission preparation were completed later on October 19, as recorded below. Signed clean-install/update tests, TestFlight installation and the App Review outcome remain open.

## 10 Signed Development qualification on October 19, 2026

The tested app and extension use the Development identities and provisioned App Group, version 2.1.0, build 15. Signatures and embedded profiles were checked for both bundles. The test Mac was registered with the team through Xcode. Personal team identifiers, account addresses, message contents and private reports are excluded from this public plan.

| Check | Result and evidence |
|---|---|
| Signed startup | User confirmed a normal settings window without storage or permission errors. |
| Mail account discovery | User confirmed the configured Mail accounts appeared. |
| Settings persistence | Selected accounts and Preview were retained after closing and reopening the app. |
| Selected-message analysis | User confirmed read-only analysis completed. |
| Callback and shared activity | Logs recorded body-request/body-ready callbacks; the Development UI count increased from four to six. |
| Own-sender protection | The 9:18 a.m. self-email was skipped as self-mail and retained in Inbox. |
| Incoming political Preview | At 9:20 a.m., logs recorded a political label and Preview outcome, with no Junk request. |
| Actual Junk action | User confirmed an incoming political email moved into Junk. |
| Restoration after restart | User restored the message to Inbox, restarted Mail and confirmed it stayed there. |
| Settings app closed | User confirmed a political email arriving at 11:20 a.m. moved into Junk while the settings app was closed. |

Times above are local to the test Mac, America/Los_Angeles. Logs establish callback and classification stages; the user observations establish the actual mailbox moves, settings UI behavior and restored-message result. These observations cover this test installation, not every provider or all classifier inputs. A production Store installation has separate storage and still requires its own qualification.

### 10.1 Development registration and lifecycle findings

The development bundle was present in the full PlugInKit registry but absent from normal Mail extension discovery when only the build-folder copies were registered. A separately named copy under `~/Applications/Mail-Filter Development.app`, followed by explicit registration of its embedded extension, appeared in normal discovery and Mail's own extension list. Use the signed build workflow for the exact staging steps.

Opening or replacing a development app can refresh its registration. During this run, Mail retained the old registration while a new registration was created for the same extension. Mail then rejected incoming requests with PlugInKit error 16, "other version in use." A clean Mail quit released the old extension process; reopening Mail restored callbacks. Quit Mail before replacing or re-registering a test extension, launch the intended settings copy, then reopen Mail. Avoid interleaving Xcode Run copies with the staged installation during a live test.

The original and development apps have separate activity stores. Verify the app identity when comparing counts. Incoming callbacks count invocations, not unique emails; body retrieval normally produces two callbacks. Preview positives appear as "Political - preview only" in Activity and do not increment Junk actions requested.

### 10.2 Store archive and local export

The signed archive stage builds with automatic development signing and production identities. The local archive at `outputs/store/Mail-Filter.xcarchive` passed archive-stage capability and profile verification. A negative check confirmed that strict distribution validation rejects that development-signed archive.

App Store export then succeeded at `outputs/store/export/Mail-Filter.pkg`. The maintained export verifier checked the Apple-issued App Store installer signature, a matching installer/app team, distribution signatures on the app and embedded extension, explicit unexpired App Store profiles, the provisioned production group, no debugging permission, matching privacy manifests and absence of engineering tools or custom installer scripts. The package was expanded into temporary files for inspection. These build commands did not install or upload it; subsequent upload and submission are recorded in Section 10.4.

The initial build-15 metadata audit found a missing `NSHumanReadableCopyright` value. The publisher approved "Copyright © 2026 Keith Holt. All rights reserved." Build 16 includes this notice in the host metadata, and the payload verifier now rejects a missing or blank notice. The replacement build-16 archive and local export passed the same capability, profile, signature and payload checks; inspecting the exported app confirmed the approved notice and matching app/extension build numbers. The previous build-15 archive and export are preserved under the ignored `outputs/store/qualification-build-15/` directory. Build 16 is a metadata update; the signed incoming-mail runtime observations above remain evidence for Development build 15. See [Apple's distribution preparation guidance](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).

### 10.3 Remaining qualification

Remaining runtime qualification includes signed setup archive import/confirmation, user-selected email-file and support-report panels, permission-denial behavior and clean-install/update recovery. Repeat the relevant checks from a final Store or TestFlight installation. The tests above do not establish App Review acceptance.

### 10.4 Upload and submission on October 19

Transporter rejected build 16 with error 90362 because the extension executable did not match its `.appex` basename. Build 17 corrected the executable name in the sandboxed configurations and added validation for this constraint. Build 18 added public Privacy Policy and Support links in Setup & help. The versioned upload package is `outputs/store/Mail-Filter-2.1.0-build-18.pkg`.

The public support and privacy pages are live at `https://keithholt.github.io/Mail-Filter/support.html` and `https://keithholt.github.io/Mail-Filter/privacy.html`. Four screenshots and synthetic reviewer samples were prepared. App Store Connect showed build 18 as Ready to Submit, and version 2.1.0 was saved with build 18 selected and the updated review notes. The publisher then reported completing submission. The selected primary category is Productivity, with Utilities secondary; Content Rights was saved by the publisher. Apple has not yet approved the submission. Automatic release after approval is selected.
