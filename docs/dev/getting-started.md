# Mail Filter Developer Getting Started

This guide is for developers who need to build, navigate, test and package Mail-Filter. Start with the scripted local build and synthetic checks, then use read-only diagnostics to investigate model behavior before testing actions in Mail. `docs/dev/architecture.md` explains subsystem contracts and invariants; the root `README.md` is the end-user guide. Detailed CLI and development timer instructions remain in `README-DEVELOPER.md`.

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

Local builds use ad hoc signing and need no paid developer account. Normal public distribution requires Developer ID certificates and notarization. Do not treat a locally verified installer as a notarized release.

## 2 Locate the code and private settings

Work from the checkout, conventionally `~/Documents/GitHub/Mail-Filter`. There is no Xcode project to open: native targets are assembled by `MacApp/build.sh`, while `Package.swift` describes the engineering CLI.

```sh
cd ~/Documents/GitHub/Mail-Filter
git status --short
xcode-select -p
xcrun swiftc --version
python3 --version
```

Read `docs/dev/architecture.md` before changing routing, concurrency, model generation or protection. Begin UI work in `SettingsView.swift` and `SettingsModel.swift`; incoming work in `NativeExtension.swift` and `NativeClassifier.swift`; model work in `PoliticalModel.swift`, `ClassificationRequest.swift` and `Core.swift`. Those files live under `MacApp/` or `Sources/MailFilter/` as shown in the architecture source map.

The native app saves local-test state under `~/Library/Application Support/Mail-Filter Local/`; release builds use an App Group container. Configure accounts through the app, not by committing personal settings. The CLI independently reads `~/.config/mail-filter/accounts.txt` and stores state under `~/.local/state/mail-filter/`. Its default prompt/evidence files come from `prompts/`, or the installed DeveloperTools resources.

Never delete private protection files to simplify a test on a working installation. Prefer temporary fixture stores or a separate macOS user. A storage-mode or signing-group change requires migration rather than an implicit reset.

## 3 Build without installing

Use the maintained scripts as the build contract. They supply compile lists, target architecture, language modes, bundle IDs, entitlements, resource copies, signing order and verification.

```sh
./MacApp/build.sh local
./build.sh
```

The native build creates `.build/mac-app/Mail-Filter.app`, its embedded `Contents/PlugIns/Mail-Filter.appex`, and `.build/mac-app/Uninstall Mail-Filter.app`. It also compiles and embeds the engineering CLI under `Contents/Resources/DeveloperTools/`. The root build creates `.build/release/mail-filter` through Swift Package Manager. Neither command installs apps, reads messages, enables extensions or requests Junk actions.

Both build scripts first regenerate the registered Word documents from Markdown. Python 3 and successful conversion are required; a documentation failure stops the build before compilation. Packaging uses the native build and inherits this step.

When adding a Swift source file, update every native target or test compilation that needs it. A file under the root package's target directory may be discovered by SwiftPM while still being absent from the explicit native lists. Inspect both build paths when changing shared code.

## 4 Run meaningful checks

```sh
./MacApp/test.sh
swift test
```

Native checks compile small Swift executables and use synthetic messages and temporary stores. They cover configuration, own-sender guards, MIME extraction, scheduling, deadlines, retries, evidence, recovery protection, migration, activity/export privacy and uninstall/PATH planning. The Swift package tests cover CLI options, parsing, evidence and state behavior. Python packaging checks verify the narrowly scoped PATH scripts against fixtures.

| Change area | Checks to prioritize |
|---|---|
| Policy or evidence | Shared filtering and model-request checks; private model comparison with positive and negative controls. |
| MIME extraction | MIME checks, including malformed alternatives and size/depth limits. |
| Retry or scheduler | Retry, deadline and burst checks; exhaustion and late-result behavior. |
| Settings or recovery | Native and Junk protection checks; stale revisions, corrupt state and imports. |
| UI diagnostics or exports | Native/diagnostic checks and explicit installed-app copy/export validation. |
| Installer or PATH | Packaging fixtures, bundle/package verification and controlled install/update/remove checks. |

Synthetic tests do not generate real model responses or prove MailKit delivered an action. A successful build also does not prove extension activation, Automation permission or shared storage access in a real session. Run the affected checks, then broaden only if new failures or changes justify it.

## 5 Package and install a local build

```sh
./MacApp/package.sh local
```

Packaging rebuilds the native product, verifies signatures and bundle identities, constructs the installer choices, expands/verifies the payload, and writes `outputs/Mail-Filter Installer.pkg`. It creates a Desktop symbolic-link shortcut to that same package. `.build/` and `outputs/` are ignored; generated developer `.docx` files are retained with their Markdown sources.

Open the package to install the apps into `/Applications`. Compatible private settings, activity and protection survive updates. The optional **Add command-line tool to PATH** choice adds only the dedicated `/etc/paths.d/org.mail-filter.command-line` entry. Unchecking it removes only a matching installer-owned entry. Open a new Terminal window for PATH changes to take effect; shell dotfiles are not edited.

Quit and reopen Mail-Filter and Mail after replacing the installed app. Confirm host and installed extension builds in the diagnostic report, check the extension in Mail Settings, and confirm saved account selection, **Enable filtering**, Preview and model readiness. Keeping an old process alive can mask a successful rebuild. The settings window can then close; Mail must stay running.

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

## 9 Keep documentation synchronized

The documentation follows Photo-Archival's split: architecture records durable design and invariants; getting-started records the repeatable developer workflow. Keep user instructions in `README.md` and engineering details in developer docs. Avoid turning the architecture guide into a chronological troubleshooting log.

```sh
python3 docs/build-docx.py
python3 docs/build-docx.py IN.md OUT.docx
python3 docs/build-docx.py --check
```

The local converter is adapted from Photo-Archival's standard-library OOXML generator. A bare run rebuilds both registered Word files; a two-path invocation converts one source; `--check` detects missing or stale registered outputs without writing. No Pandoc or third-party Python package is required. ZIP timestamps are fixed so unchanged inputs produce identical bytes.

Edit Markdown only, regenerate, validate the package/XML and check Word rendering before committing the `.md` and `.docx` together. Headings, prose, inline emphasis/code/links, lists, pipe tables and fenced code diagrams are supported. Keep diagram and command lines short enough for the page. If introducing unsupported Markdown, extend the converter in the same change. Normal builds regenerate the Word files automatically; a documentation-only edit can use the converter directly without rebuilding or installing the app.

## 10 Review checklist

- Review source-map accuracy and behavioral limits against the code.
- Keep String generation; validate model changes with private controls and relevant checks.
- Verify settings, Preview, own-sender and restored-message protection across updates.
- Exclude real mail, accounts, credentials and reports; regenerate and review both doc formats.
