# Mail Filter App Store Deployment Plan

Mail-Filter can retain its current MailKit and on-device classification architecture for a Mac App Store edition. The recommended approach is one shared code base with separate build configurations for local engineering, sandboxed development, and Store distribution. Support logging should remain available in the Store edition. Different builds are needed for signing, capabilities, development tools and installation behavior, rather than to make log files possible.

Desktop probes confirm that App Sandbox permits our synthetic model classification, private file logging and settings storage. A Mail-targeted Apple Events exception also permits the account-count query; compose-only permission fails that query. Use the targeted exception as the candidate for signed qualification of account setup and selected-email diagnostics. Provide an address-based setup and email-file analysis fallback if automation is unavailable or unacceptable to App Review. A successful runtime test does not guarantee entitlement acceptance or App Store approval.

Assessment date: October 17, 2026. Baseline: build 13, commit `2cee33b`. The checks used an Apple silicon Mac with macOS 27.0.1, Xcode 27.0 and SDK 27.0. This plan records completed checks separately from the desktop, provisioning and review gates that remain open.

Implementation update: build 15 uses one root Xcode project for local and Store builds. Store preparation includes manual address setup, email-file diagnostics, complete setup archives and bounded private file history. An unsigned archive compiles and passes payload inspection. Apple enrollment is processing. Section 9 records the completed work and the tests that must wait for signing. The working installation has not been replaced.

## 1 Feasibility findings

Apple explicitly supports distributing MailKit extensions through the Mac App Store. Our incoming handler already obtains message data and requests Junk actions through that public API. The settings application, packaging and supporting diagnostics require the larger changes. See [Apple MailKit presentation](https://developer.apple.com/videos/play/wwdc2021/10168/) and [App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

The current native settings application is not sandboxed. Its embedded extension is sandboxed and uses a narrow local-development filesystem exception. The existing release script supports Developer ID distribution with an App Group, but still leaves the host application unsandboxed. Neither configuration is a complete App Store configuration.

| Check | Result | Evidence and limit |
|---|---|---|
| Existing regression suite | Passed | All named checks in `MacApp/test.sh` passed, including recovery, retries, MIME, settings and diagnostics. |
| Offline Store scenarios | Passed | Ten additional checks cover address-based routing, email-source decoding, migration and private activity. |
| Probe compilation and signatures | Passed | Four isolated app bundles compile and their ad-hoc signatures and entitlement dictionaries verify. |
| Container logging and storage | Passed in desktop probes | All four variants round-trip synthetic settings, activity and an owner-only log file. Logger calls complete and the current-process log store opens. |
| Basic sandbox process | Passed in desktop probes | All three sandboxed variants exit successfully and report a containerized home directory. |
| Sandboxed Mail automation | Partial desktop evidence | The Mail-targeted exception reads account and selection counts. Compose-only metadata access fails with privilege error -10004. No selected-message source was tested. |
| Synthetic model generation | Passed in desktop probes | All four variants classify the synthetic campaign appeal as political using the shared model code. |
| Provisioned App Group | Not established | This Mac has zero valid Apple signing identities. A real team-authorized group has not been tested. |

The user ran the complete matrix from a normal Terminal session on October 17, 2026. All four variants completed with exit code zero, verified signatures and matching entitlement dictionaries. The three sandboxed variants confirmed containerized storage. Their observed differences were limited to Mail automation in this run:

| Variant | Mail preflight | Read-only metadata result |
|---|---|---|
| Baseline without sandbox | 0 | Account and selection counts read successfully. |
| Sandbox without Mail entitlement | -600 | No metadata query attempted after unsuccessful preflight. |
| Sandbox with compose group | 0 | Metadata script rejected with -10004, an Apple Events privilege error. |
| Sandbox with Mail-targeted exception | 0 | Account and selection counts read successfully. |

Mail was visible as running to every variant. No message was selected, so the successful metadata queries did not exercise the selected-source branch. Preflight success alone does not prove that a particular Apple Event is allowed, as the compose result demonstrates. The plain sandbox's -600 is `procNotFound` in the SDK; it does not mean Mail was closed, and this run did not isolate its cause.

Earlier attempts inside the restricted execution environment could not launch the sandbox helper or complete synthetic generation, and did not see Mail. The successful desktop run establishes that those outcomes are not reproducible in the normal session. It does not identify their precise cause. Provisioned host/extension sharing, selected-message source access, permission denial and Store archive behavior remain separate qualification tasks.

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

Owner: account holder with engineering support. Decide individual or organization enrollment, obtain membership, and authorize the team. Register development and production host/extension identifiers and separate App Groups. Establish certificate custody and roles. The exit condition is a signed development archive whose declared capabilities match its profiles, without modifying the working installation.

### 6.2 Add a Store build pipeline

Owner: engineering. Add an Xcode project or equivalent reproducible Xcode archive setup for the host and embedded extension. Preserve the current shell entry points and document the mapping to the new targets. Add sandboxed development and Store Release configurations, explicit feature capabilities, privacy resources, version metadata and archive validation. Leave standalone CLI compilation intact.

Primary files are the new project/configuration files, `MacApp/build.sh`, `MacApp/package.sh` and the bundle-verification scripts. Keep direct packaging separate from Store archiving. Verify that the Store payload contains only the intended application and extension, then upload a validation build before investing in final listing materials.

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
| Publisher and signing | Pending account holder | Active membership, valid identities and authorized profiles |
| Sandboxed desktop startup | Ad-hoc probes passed | Host and extension launch from the provisioned archive |
| Shared storage | Open | Both processes read/write the intended group without development exceptions |
| Setup capability | Account-count probe passed | Full inventory and selected-source access qualify with acceptable entitlements, or the manual path is complete |
| File selection and export | Open | Open/Save access works without broad filesystem exceptions |
| Model execution | Sandboxed synthetic appeal passed | Controls and representative consented fixtures work inside the distributed extension |
| Migration and recovery | Complete archive fixture checks passed | Signed import and restored-message protection survive update and restart |
| Store diagnostics | Container and fixture checks passed | Useful bounded reports after host quit, extension restart and log-service failure |
| Mail actions | Pending isolated live test | Controlled eligible test mail moves; restored false positive stays in Inbox |
| Store archive | Unsigned archive and payload checks passed | Provisioned archive validates for App Store Connect |
| App Review | Open | Submitted build and requested entitlements accepted |

No gate should be marked passed solely because an ad-hoc signature verifies or the unsandboxed CLI works. Keep the archived build, signed entitlements, OS/Xcode versions and reproduction steps with each qualification result. Store actual test reports outside public documentation if they contain user data.

## 8 Immediate next actions

1. Complete Apple enrollment, then confirm identifiers, group registration and the signing team. The desktop probes and unsigned implementation checks are complete; provisioning and upload qualification depend on the account.
2. Build the isolated signed development configuration. Qualify App Group sharing, full inventory, selected-message source, permission denial, file panels and import confirmation before enabling any apply-mode test.
3. Complete the isolated Mail action/update matrix, publish support and privacy URLs, and settle the review metadata. Keep the existing working installation and developer CLI available during this work.
4. Validate the production archive, beta through TestFlight, and prepare the review submission after the technical gates pass.

## 9 Work completed while enrollment processes

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

The native regression suite passes, including 42 dedicated checks for manual setup, complete migration, protection retention, import confirmation, email-file extraction, export privacy, log rotation, expiry and log-storage failure. All use synthetic input and temporary stores. The actual Store host and extension compile and archive with signing disabled, and payload inspection passes. These results do not establish signed runtime access, UI behavior under Powerbox, live Mail actions or model accuracy in the distributed extension.

`MacApp/Store/README.md` contains the commands for signed development, production archiving and local export after enrollment. `docs/store-review-preparation.md` provides listing, privacy-policy and entitlement drafts plus a reproducible reviewer demonstration. Public support/privacy URLs, contact details, screenshots and final business/compliance answers remain publisher work. Signed clean-install/update tests, TestFlight and App Review remain open.
