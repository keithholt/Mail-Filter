# Mail Filter Developer Getting Started

This guide is for developers who need to build, navigate, test and package Mail-Filter. Start with the isolated signed Dev build and synthetic checks, then use read-only diagnostics to investigate model behavior before testing actions in Mail. `docs/dev/architecture.md` explains subsystem contracts and invariants; the root `README.md` is the end-user guide. Detailed CLI and development timer instructions remain in `README-DEVELOPER.md`.

Markdown is the source of truth. This guide and the architecture guide have generated Word copies beside their sources, following the same documentation process as Photo-Archival. Edit the `.md` files and regenerate both formats together.

## 1 Required environment

| Requirement | Purpose | Check |
|---|---|---|
| Apple silicon Mac on macOS 26 or later | Current native target and on-device inference. | `sw_vers` and `uname -m` |
| Full Xcode with first-launch setup complete | MailKit/Foundation Models SDK and native build tools. | `xcode-select -p` and `xcrun swiftc --version` |
| Swift tools 6.2 or later | Root Swift package manifest. | `swift --version` |
| Python 3 | Bundle/package checks and Markdown-to-Word conversion. | `python3 --version` |
| Git | Source control. | `git --version` |
| Apple Intelligence enabled with model ready | Real classification tests; not synthetic checks. | App model status or CLI `--check` |

In Xcode Settings, under Locations, select the intended Xcode installation as Command Line Tools. The SDK must include the Foundation Models APIs used by this checkout. The package and native scripts use different Swift language modes deliberately; a newer compiler alone is not a reason to unify them.

Local builds use ad hoc signing and need no paid developer account. Public direct downloads require Developer ID certificates and notarization; Store distribution uses its own signing and review workflow. Do not treat a locally verified installer as a notarized release.

## 2 Locate the code and private settings

Work from the checkout, conventionally `~/Documents/GitHub/Mail-Filter`. Open the root `Mail-Filter.xcodeproj` for native development. It owns the app, extension, CLI and uninstaller targets for every distribution channel. `MacApp/generate-project.py` is the source-list authority. Shell entry points invoke the same project; `Package.swift` additionally supports standalone CLI development and tests.

```sh
cd ~/Documents/GitHub/Mail-Filter
git status --short
xcode-select -p
xcrun swiftc --version
python3 --version
```

Read `docs/dev/architecture.md` before changing routing, concurrency, model generation or protection. Begin UI work in `SettingsView.swift` and `SettingsModel.swift`; incoming work in `NativeExtension.swift` and `NativeClassifier.swift`; model work in `PoliticalModel.swift`, `ClassificationRequest.swift` and `Core.swift`. Those files live under `MacApp/` or `Sources/MailFilter/` as shown in the architecture source map.

The legacy Local configuration saves state under `~/Library/Application Support/Mail-Filter Local/`. Mail-Filter Dev and Store use different provisioned App Group containers, so their setup, activity and recovery files remain separate. Configure accounts through the app, not by committing personal settings. The CLI independently reads `~/.config/mail-filter/accounts.txt` and stores state under `~/.local/state/mail-filter/`. Its default prompt/evidence files come from `prompts/`, or the installed DeveloperTools resources.

Never delete private protection files to simplify a test on a working installation. Prefer temporary fixture stores or a separate macOS user. A storage-mode or signing-group change requires migration rather than an implicit reset.

## 3 Build without installing

### Open the root project

```sh
open Mail-Filter.xcodeproj
```

Open the project file explicitly. Opening the repository folder can instead load the CLI's Swift package and expose its separate schemes. The native navigator follows the repository's actual top-level folders. Source files stay in place; there are no navigation symlinks or copies. Git's public inventory omits ignored private settings and generated outputs. Explicit target source lists determine compilation, independently of navigation.

The same `MailFilter` and `MailFilterExtension` targets build every app variant. Building the host builds and embeds its extension. `MailFilterCLI` and `MailFilterUninstaller` are separate native targets used by direct builds. The Store scheme's dependency graph excludes them.

| Scheme | Purpose |
|---|---|
| Mail-Filter Dev | Build and run the signed sandboxed app with separate settings and extension beside Store. |
| Mail-Filter Local | Build the legacy direct app, extension, CLI and uninstaller; shares the production app identity. |
| Mail-Filter Local Installer | Build native direct products, then create and verify the installer. |
| Mail-Filter Store | Signed sandboxed Development for Build/Run; Store configuration for Archive. |
| Mail-Filter Build Check | Unsigned sandboxed app/extension compilation with development identities; no runnable. |
| mail-filter CLI | Native CLI; Run defaults to harmless `--help`. |

Only the Store scheme enables Archive. Use the installer or release packaging scripts for direct distribution.

For development beside Store, select **Mail-Filter Dev**, choose **My Mac**, and press Command-B. Run launches the signed Development app with separate identifiers and storage. The legacy Local scheme retains the production identity and must not replace or compete with a working Store installation. Quit Mail before deliberately testing a replacement extension. Building alone does not install or activate the extension or change filtering settings. Xcode records built app paths with Launch Services, so use a separate macOS test user for live extension qualification.

Select **Mail-Filter Build Check** for unsigned sandboxed compilation without an Apple Account or certificates. This scheme uses isolated development identifiers and has no runnable. It cannot qualify runtime permissions or shared App Group access. Use the Issue navigator with Command-5 to inspect build errors.

Xcode may also expose automatic component schemes. Their default configuration is Local, so compiling the extension alone does not require a paid team. Use a host scheme for normal development; MailKit still needs its containing app for installation and activation.

### Create the local installer inside Xcode

Select **Mail-Filter Local Installer**, then choose **Product > Build** or press Command-B. Its native dependencies build the app, extension, CLI and uninstaller first. The packaging phase stages copies of those products, adds the engineering CLI and its resources to the staged app, reseals its signature, and verifies the installer. It does not start another `xcodebuild` or maintain a second Swift compile list.

The output is `outputs/Mail-Filter Installer.pkg`. The packager maintains a Desktop shortcut to that same file and leaves unrelated Desktop items untouched. Building creates the package; open it yourself to install. It does not launch Installer, change installed apps, filtering settings or PATH, or enable extensions. The package uses ad hoc signing and requires no paid developer membership.

Each explicit installer build reruns packaging. Use **Mail-Filter Dev** for normal signed incremental development or **Mail-Filter Build Check** for unsigned Store compilation. Only the packaging helper disables Xcode's build-script sandbox, because it writes repository outputs and the Desktop shortcut. This is separate from the app's runtime sandbox, which is controlled by its distribution configuration.

### Configure signed Xcode builds

After the paid developer team is active, register the Store app, extension and shared-group identifiers in `MacApp/Store/README.md`. Sign in under Xcode Settings, Apple Accounts, and create or download signing assets. Copy `MacApp/Build/Signing.example.xcconfig` to `Signing.local.xcconfig` in the same directory and set `DEVELOPMENT_TEAM` to the actual ten-character Team ID. Git ignores it. An existing local signing file from the old Store directory should be moved to this new location rather than committed.

The **Mail-Filter Store** scheme uses Development for Build/Run and Store for Archive. Those configurations share sandboxed capabilities but have separate bundle IDs and App Groups. DeveloperID uses Developer ID signing for direct downloads; Local uses ad hoc signing and retains the existing local-development settings directory. BuildCheck disables signing even when the private team file exists. The configuration files under `MacApp/Build/` define these differences; do not overwrite generated target settings with team overrides.

Store archiving uses automatic development signing. App Store export applies distribution signing and final profiles; do not force Apple Distribution into the automatic archive build. Archive verification and strict distribution verification are separate stages. An archive passing its stage is not permission to upload or publish it.

Before enabling a signed development extension, qualify group sharing, migration, file panels and Mail permissions in an isolated setup. Do not enable multiple filtering extensions against the same working inbox. Compilation and signature checks do not establish signed runtime or App Review acceptance.

### Stage a Development extension for Mail testing

Quit Mail and the development settings app before replacing or registering a test bundle. Build with **Mail-Filter Dev**, **My Mac**, **Product > Build**, or use `MAIL_FILTER_TEAM_ID=YOURTEAMID ./MacApp/store-build.sh development` from the repository root. The shell workflow uses the actual Mac as its destination and lets Xcode create/download profiles and register that Mac if needed.

Prefer `MAIL_FILTER_TEAM_ID=YOURTEAMID ./MacApp/install-dev.sh` to build, verify and stage the isolated app. Use `--no-build` to stage an already verified Development product. The script preserves an existing staged copy under ignored outputs/development, rejects replacement of an in-use Dev bundle and never activates the extension or imports settings.

For manual first installation, copy the signed Development `Mail-Filter.app` to your user Applications folder and name the copy `Mail-Filter Dev.app`. The shell build is under `.build/xcode-derived/Build/Products/Development/`; an Xcode build uses its selected Derived Data directory. For an update, replace the complete development app bundle while Mail and the settings app are closed. Preserve its separate App Group data. Do not replace the working `/Applications/Mail-Filter.app` to perform this test.

Register and open the staged copy:

```sh
/usr/bin/pluginkit -a "$HOME/Applications/Mail-Filter Dev.app/Contents/PlugIns/Mail-Filter.appex"
/usr/bin/open -a "$HOME/Applications/Mail-Filter Dev.app"
```

Open this settings app before reopening Mail. Confirm the saved accounts and enable Preview first. Reopen Mail, then use **Mail > Settings > Extensions** to enable **Mail-Filter Dev** and disable the original filter during the controlled test. A full registry entry alone is insufficient: normal discovery with `pluginkit -m -v -p com.apple.email.extension` must list the staged copy. Registration does not silently enable it.

Do not rebuild, replace or re-register the active development bundle while Mail hosts it. Re-registering during a live session caused PlugInKit error 16, "other version in use," in the October 19 qualification. A clean Mail quit, completed staging and a fresh Mail launch released the stale instance. If an extension is missing, compare normal discovery with the full registry and Mail's logs rather than repeatedly sending test emails.

The original settings app and development settings app have separate counters. Incoming callbacks normally increase by two for one message: before and after the body is fetched. Self-mail should be kept. A Preview positive appears in Activity without a Junk action request; turn Preview off and save only for the controlled move test. Also verify restoring a moved message, restarting Mail and receiving mail with the settings app closed. The dated results are in the deployment plan.

### Archive and export for App Store Connect

Use **Mail-Filter Store > Product > Archive** in Xcode for the production identity, then use Organizer for validation and distribution. The shell equivalents create local artifacts:

```sh
export MAIL_FILTER_TEAM_ID=YOURTEAMID
./MacApp/store-build.sh archive
./MacApp/store-build.sh export
```

The archive is `outputs/store/Mail-Filter.xcarchive`; the exported package is `outputs/store/export/Mail-Filter.pkg`. The commands refuse to overwrite an existing archive or export directory. Preserve completed artifacts before creating a replacement. Automatic provisioning can create/download signing assets; export uses the explicit local `destination=export` setting and does not upload.

The archive's development signature is checked with the verifier's explicit archive mode. The exported package passes a separate strict verifier that checks its installer signature, matching signing team, distribution-signed app/extension, unexpired App Store profiles, no debugging permission, provisioned group, privacy manifests and engineering-payload exclusions. Never treat a development archive as a validated distribution package.

Create the App Store Connect app record before upload, using the production bundle ID. Confirm current agreements and publisher roles. Local package verification is distinct from App Store Connect validation, TestFlight, App Review and release approval. Public support/privacy URLs, screenshots and a reproducible synthetic review demonstration remain publisher preparation tasks.

### Use the same targets from Terminal

```sh
./MacApp/build.sh local
./MacApp/package.sh local
./MacApp/store-build.sh check
./build.sh
```

`MacApp/build.sh` invokes the root project's Local scheme, stages the products under `.build/mac-app/`, embeds the CLI under `Mail-Filter.app/Contents/Resources/DeveloperTools/`, and verifies signatures and payloads. `package.sh` uses those staged products to create the direct installer. The Xcode installer scheme bypasses this build wrapper because its target dependencies have already compiled the products; it uses the same staging and package verification functions.

`store-build.sh check` invokes the same host and extension targets with Store settings, disables signing and substitutes development identities. It verifies an unsigned archive at `.build/store-unsigned.xcarchive`. All native configurations share `.build/xcode-derived/`, with products separated by configuration. None of these commands installs or activates the filter or requests Mail actions.

Every native build depends on `MailFilterDocumentation`, which regenerates all registered Word documents before compilation. Its script declares the Markdown inputs and Word outputs and retains Xcode's script sandbox. Missing Python or failed conversion stops the build. This applies equally to Xcode builds and the shell wrappers. The root `build.sh` separately regenerates docs before building the standalone Swift package CLI at `.build/release/mail-filter`.

After adding source files, update `MacApp/generate-project.py` and run:

```sh
python3 MacApp/generate-project.py
python3 MacApp/generate-project.py --check
```

The generated project and shared schemes are checked in. Git's inventory supplies navigator references, while the generator's target lists supply membership. The CLI source directory is discovered by both the generator and SwiftPM. No shell script has an independent app or extension compile list. Development checks allow named Xcode debug/preview libraries; the production Store verifier still requires a release executable alone.

## 4 Run meaningful checks

```sh
./MacApp/test.sh
./test.sh
```

Native checks compile small Swift executables and use synthetic messages and temporary stores. FailureInjectionChecks exercises the real production pipeline with scripted empty/blank/malformed replies, refusals, context and temporary errors, missing keyword evidence, attempt/overall timeouts, uncooperative late positives, duplicate bursts, queue overflow, cancellation and settings/protection changes during inference. It also verifies that an empty keyword list disables only keyword validation, and preserves negative/error, Preview and identity guards. No actual model or Mail call occurs in these fault scenarios. They cover configuration, own-sender guards, MIME extraction, scheduling, deadlines, retries, evidence, recovery protection, migration, activity/export privacy and uninstall/PATH planning. The Swift package tests cover CLI options, parsing, evidence and state behavior. Python packaging checks verify the narrowly scoped PATH scripts against fixtures.

| Change area | Checks to prioritize |
|---|---|
| Policy or evidence | Shared filtering and model-request checks; private model comparison with positive and negative controls. |
| MIME extraction | MIME checks, including malformed alternatives and size/depth limits. |
| Retry or scheduler | Retry, deadline and burst checks; exhaustion and late-result behavior. |
| Settings or recovery | Native and Junk protection checks; stale revisions, corrupt state and imports. |
| UI diagnostics or exports | Native/diagnostic checks and explicit installed-app copy/export validation. |
| Installer or PATH | Packaging fixtures, bundle/package verification and controlled install/update/remove checks. |

Synthetic tests do not generate real model responses or prove MailKit delivered an action. A successful build also does not prove extension activation, Automation permission or shared storage access in a real session. Run the affected checks, then broaden only if new failures or changes justify it.

### Qualify timing and queued inference

The normal native suite includes accelerated timing tests and 200 model-slot cancellation/handoff races. Run production-duration qualification separately from the repository root, using a new output file whose parent exists:

```sh
./MacApp/qualify-timing.sh --full \
  --output /private/tmp/mail-filter-full-timing.json
```

It takes about three minutes. It runs the actual native retry/scheduler/parser/action-gate code with temporary stores and scripted SDK calls, real 20-second attempt and 60-second overall limits, and actual 1-/2-second delays. It checks legacy overlap, corrected SDK serialization, before/after-deadline replies, late positives, slow multi-section exhaustion, the next queued message and cancellation while waiting. It generates no real model response and makes no Mail call. Its intended-action counters belong only to temporary state. Reports identify each scenario, retain a monotonic timeline and report individual checks for the total-budget case.

For the actual model comparison on this Mac, run:

```sh
./MacApp/probe-model-queue.sh \
  /private/tmp/mail-filter-real-model-queue
```

Use a new directory. This experiment reconstructs the historical unbudgeted JSON request from Git as data, uses fictional token-dense tracking links, and then compares queued and paced native processing under fixed policy/budgets. It performs 16 message trials in AB/BA blocks and saves requests, replies, usage, timings and the historical contract. There is no Mail access, actual move, installed-app replacement or production-settings change. Keep outputs out of Git. A recreated context overflow or an injected timeout does not prove the remote invalid-label error has the same cause.

Read the [timing and queue investigation](../timing-and-queue-investigation.md) and [original failure history](../model-failure-history.md) before changing retry budgets. Smaller sections reduce individual request size while potentially increasing total attempt time. Queue admission begins the 60-second budget; earlier waiting time is separate. The SDK gate is process-local, and a never-returning framework call cannot be forcefully retired through this code. Store review remains on hold.

### Test mail sent to yourself

In **Mail-Filter Dev**, open Filtering and turn on **Filter mail from my own addresses (testing)**, then **Save Settings**. This switch is off by default and appears only in the signed Development configuration. It allows mail from any configured own address, including unchecked accounts, to reach classification when delivered to a selected recipient. Preview, keyword validation, meaningful-body and recovery checks still apply. For actual Junk moves, turn Preview off and save; enable only the Dev extension for the designated test setup. Send a fresh message for each action test because previously moved/restored messages remain protected. Turn the testing switch off and save when finished.

The Store build has no self-mail switch and ignores its saved key if present in an imported Dev setup. The native suite compiles the injected pipeline twice, checking production exclusion and Dev opt-in, cross-account self-mail, Preview, evidence, pause, recovery and settings changes during inference. It never moves real mail.

### Compare response and section budgets

Build 24 records content-free per-request measurements in support reports. `modelEmptyResponse` means zero or whitespace-only classification text; `invalidModelResponse` means nonempty text outside the accepted label format. On macOS 27, compare visible response length with actual output and reasoning token counts. The output-limit flag does not itself prove truncation or a model defect. Memory-pressure notifications may be unknown; installed RAM alone does not establish pressure.

Use a normal Terminal session on the affected Mac for this read-only controlled comparison:

```sh
./MacApp/probe-model.sh --compare-request-budgets REPORT.json
```

Pass an explicit selected-email export to avoid picking up other Desktop reports. The experiment compares 6,000 versus 3,000-character section limits and 64 versus 256 output tokens, with the same exported policy and content. It also runs short and long synthetic receipt/campaign controls. It does not retry each trial; each generated section has its own measurements. Trial order and model warm-up can influence timing, so repeat comparisons before attributing a difference to one setting.

For synthetic inputs only, without reading email reports or accessing Mail:

```sh
./MacApp/probe-model.sh --compare-request-budgets --synthetic-only
./MacApp/probe-model.sh --stress-model --synthetic-only
./MacApp/probe-model.sh --probe-output-limits --synthetic-only
```

The owner-only output is `~/Desktop/Mail-Filter Request Budget Comparison.json`. Real-email comparisons contain private message/model text; keep them outside Git. Share the explicit report together with the normal support report when investigating a failure. Build 24 production uses the 3,000-character/256-token combination, with retries at 1,500 characters and unchanged 20/60-second deadlines; this command changes no filtering settings or mailbox contents. The local synthetic matrix does not reproduce or prove resolution of the original failure. Keep review on hold until a plausible matching failure has been reproduced and the mitigation demonstrated. Keep debugging on the publisher’s Mac using the local reproduction plan. The remote family member is only a beta tester; neither extra passing controls nor a different hardware specification establishes the original failure’s cause.

The stress probe compares the exact previous standard policy with the candidate policy, captures response scalars and evaluates the approved build's parser. The output-limit probe intentionally uses tiny response limits as a truncation control; failure at one or two tokens is not evidence that the shipped 64-token budget caused a failure. Reports are private Desktop files and must not become committed email fixtures. The 48 local stress trials passed without reproducing the affected Mac's first-attempt failure. Review remains on hold until a plausible matching scenario is recreated and a mitigation is demonstrated; passing injected faults alone does not satisfy that gate.

## 5 Package and install a local build

```sh
./MacApp/package.sh local
```

Packaging rebuilds the native product, verifies signatures and bundle identities, constructs the installer choices, expands/verifies the payload, and writes `outputs/Mail-Filter Installer.pkg`. It creates a Desktop symbolic-link shortcut to that same package. `.build/` and `outputs/` are ignored; generated developer `.docx` files are retained with their Markdown sources.

Quit Mail, Mail-Filter and its uninstaller **before** opening the package to install into `/Applications`. Installer uses a native close-app requirement, plus a read-only preinstall check across users. It stops before replacement if an old extension process remains or process inspection fails. If Mail has quit but the extension does not exit, restart the Mac before retrying. The guard never terminates apps or changes private settings. Compatible private settings, activity and protection survive updates. The optional **Add command-line tool to PATH** choice adds only the dedicated `/etc/paths.d/org.mail-filter.command-line` entry. Unchecking it removes only a matching installer-owned entry. Open a new Terminal window for PATH changes to take effect; shell dotfiles are not edited.

After installation, open Mail-Filter and reopen Mail. Compare the sidebar build with **Mail-Filter (build 21)** in Mail Settings, using the current build number. Confirm saved accounts, **Enable filtering**, Preview and model readiness. Activity retains the last extension startup build and time; application diagnostics also record its process ID. This is historical evidence, not a liveness check, and earlier builds have no startup identity. Verify a new incoming callback after the update; old Inbox messages are not replayed. The settings window can then close; Mail must stay running.

A fresh native setup defaults to apply mode once configured. Use Preview for initial validation and keep it saved while testing. Updating does not automatically scan older Inbox messages. Own-sender mail is protected, so sending to yourself can exercise callback delivery but is not a positive-classification test.

## 6 Investigate a missed email

Start with the exact email, its diagnostic key, installed builds and retained automatic history. Separate four questions: Did Mail deliver usable content? Did the model return a valid label? Did a positive pass evidence verification? Did the extension request Junk? A current Analyze result is a new classification under current policy, not a record of the original decision.

1. Select exactly one message in Mail. In Activity, use **Analyze selected email** for a read-only result, then **Copy analysis result** if needed.
2. Use **Export selected email report** to save its JSON source, decoded excerpt, current policy and retained history. Export does not move the email or require analysis first.
3. Use the separate **Copy diagnostic report** control for application state and content-free logs. It does not copy the selected-email result.
4. Match the opaque key across body requests, queue admission, analysis attempts, labels and final outcomes. Missing retained history can reflect retention or storage failure.

| Observed stage | Investigation |
|---|---|
| No usable body callback | Extension enablement/registration, raw-body delivery and `bodyUnavailable`; a restart alone is not a classification test. |
| MIME review category | Decode the private exported source and inspect the bounded extractor. |
| Skip or protection | Check selected delivery recipients, own-sender addresses and persisted identity. |
| `queueFull` or model failure | Inspect admission, failure category, retry attempts and deadlines. |
| `modelNotPolitical` | Compare the actual extracted excerpt and saved policy; keyword presence cannot override a negative. |
| Positive without Junk request | Evidence rejection, Preview, pause/revision changes or protection/storage errors. |
| `junkRequested` | Check Mail's Junk mailbox and synchronization; the record is a request, not a move confirmation. |

For read-only model reproduction from a normal Terminal session:

```sh
./MacApp/probe-model.sh --verify-supported-path
./MacApp/probe-model.sh --investigate-refusal
```

These read exported reports from Desktop, or accept explicit export paths. They test the current string interface with synthetic receipt/campaign controls; the second command adds historical guided/tagging comparisons and hostname-only link experiments. They do not access Mail, move messages or write filtering settings. Outputs contain private diagnostic data and belong outside the repository. A sandboxed execution service may fail to access Apple's model even when the user's Terminal works.

The shared CLI provides further engineering entry points:

```sh
.build/release/mail-filter --check
.build/release/mail-filter --fixture fixtures/sample.json
.build/release/mail-filter --account 'example.org' --dry-run --limit 2
```

The last command reads real mail but explicitly disables moves. Use your actual account privately. A normal CLI run without diagnostic or `--dry-run` arguments applies verified matches by default; do not use it as a read-only test. The fixture path never accesses Mail. Full CLI flags, state semantics and development timer commands are in `README-DEVELOPER.md`.

## 7 Validate a change before release

Keep a private reproduction for each reported failure and pair it with an ordinary negative control. Test extraction, label validity, political accuracy and verified evidence separately. Never commit real mail exports, account files, email addresses, local settings or raw MIME as public fixtures. Convert regression cases into synthetic examples that preserve the relevant structure.

For action testing, use a controlled account or a separate macOS user and explicitly verify the mailbox outcome. Check Preview makes no action/reservation, pause or policy changes invalidate an in-flight result, and a message manually restored from Junk stays protected after restart. Exercise update, custom-policy retention, migration and optional PATH removal. Do not reset the working user's recovery data or force old Inbox messages through production filtering to obtain a test result.

Local checks can establish code contracts; actual model behavior and Mail delivery require installed-app evidence. Document those separately in change descriptions. A few successful model controls do not establish accuracy on every email, and there is no guaranteed retry of callbacks dropped by Mail or queue overflow.

## 8 Release signing and distribution

Use a Developer ID Application identity, Developer ID Installer identity and team ID supplied through the existing environment variables:

```sh
export MAIL_FILTER_TEAM_ID='YOURTEAMID'
export MAIL_FILTER_SIGN_IDENTITY='Developer ID Application: Example (YOURTEAMID)'
export MAIL_FILTER_INSTALLER_IDENTITY='Developer ID Installer: Example (YOURTEAMID)'
./MacApp/package.sh release
export MAIL_FILTER_NOTARY_PROFILE='mail-filter-notary'
./MacApp/notarize.sh
```

Configure the named notarytool Keychain profile separately; credentials do not belong in source or documentation. Release scripts require matching team/group entitlements, hardened runtime and valid signing identities. They submit, staple and assess the installer through the existing notarization workflow. Test the signed product's App Group access and clean-Mac installation before publishing. Release storage differs from local test storage, so preserve and explicitly import existing settings/protection when migrating.

## 9 Store preparation

For Store preparation, run `./MacApp/store-build.sh check`. It regenerates docs, compiles an unsigned archive with development identities and checks the Store payload. It does not establish signed runtime behavior. `MacApp/Store/README.md` explains signed development, production archive and local export once the team is available. Do not open an unsigned check product or enable another extension against the working inbox.

The app can now configure addresses manually and analyze an opened `.eml` without Mail automation. Export Setup produces a private archive containing settings and restored-message protection. Import preserves pause/preview, inventory and aliases, then waits for explicit confirmation before filtering. The importer can also read an explicitly selected legacy folder containing both settings and protection; it refuses to silently omit missing protection. Keep the source and private destination backup until the transition is verified.

Store support reports use bounded private file history and a Save panel. The direct build can additionally collect its own unified logs. Native checks include synthetic complete-migration, import-confirmation, manual-account, email-file and rotation/expiry failures. Real file-panel permissions, provisioned group sharing, signed model inference and mailbox actions remain separate qualification steps.

## 10 Keep documentation synchronized

The documentation follows Photo-Archival's split: architecture records durable design and invariants; getting-started records the repeatable developer workflow. Keep user instructions in `README.md` and engineering details in developer docs. Avoid turning the architecture guide into a chronological troubleshooting log.

```sh
python3 docs/build-docx.py
python3 docs/build-docx.py IN.md OUT.docx
python3 docs/build-docx.py --check
```

The local converter is adapted from Photo-Archival's standard-library OOXML generator. A bare run rebuilds all registered Word files; a two-path invocation converts one source; `--check` detects missing or stale registered outputs without writing. No Pandoc or third-party Python package is required. ZIP timestamps are fixed so unchanged inputs produce identical bytes.

Edit Markdown only, regenerate, validate the package/XML and check Word rendering before committing the `.md` and `.docx` together. Headings, prose, inline emphasis/code/links, lists, pipe tables and fenced code diagrams are supported. Keep diagram and command lines short enough for the page. If introducing unsupported Markdown, extend the converter in the same change. Normal builds regenerate the Word files automatically; a documentation-only edit can use the converter directly without rebuilding or installing the app.

## 11 Review checklist

- Review source-map accuracy and behavioral limits against the code.
- Keep String generation; validate model changes with private controls and relevant checks.
- Verify settings, Preview, own-sender and restored-message protection across updates.
- Exclude real mail, accounts, credentials and reports; regenerate and review both doc formats.
