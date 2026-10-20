# Mail-Filter developer guide

The native settings app and MailKit extension are the user-facing product. The Swift command-line tool is still maintained for engineering, diagnostics and fixture testing; its timer-based baseline is tagged `v1.0.0`. The native build and installer do not replace or remove it.

For a source-code introduction, start with the [developer getting-started guide](docs/dev/getting-started.md) and [architecture and source map](docs/dev/architecture.md). Both have generated Word copies in `docs/dev/`; see the [documentation workflow](docs/README.md). This file retains the detailed CLI reference and engineering notes. These additional guides are in the source checkout, rather than the installed DeveloperTools folder.

The [App Store deployment plan](docs/app-store-deployment-plan.md) records feasibility results, developer membership requirements, build configurations, logging and the remaining signing/desktop/review gates. Its isolated checks are documented in [MacApp/Feasibility](MacApp/Feasibility/README.md); they do not change the installed filtering app.

## Native app development

Full Xcode with first-launch setup completed, macOS 26+, Apple silicon and Python 3 are required. Build and verify from the checkout:

```sh
./MacApp/test.sh
./MacApp/package.sh
```

Packaging builds the settings app, extension and uninstaller, verifies the installer, and writes `outputs/Mail-Filter Installer.pkg`. It then creates `~/Desktop/Mail-Filter Installer.pkg` as a symbolic-link shortcut to that package. Rebuilding replaces the package at the same location, so the shortcut opens the latest build without retaining a stale copy. An existing unrelated Desktop item is preserved; a warning reports conflicts or denied Desktop access without failing a successfully verified package. If macOS asks, allow the build's Terminal application access to Desktop. The package remains available in `outputs/` if the shortcut cannot be created.

`./MacApp/build.sh` invokes the root Xcode project and stages the application bundles in `.build/mac-app/`, including a separately compiled CLI and generic developer resources. It creates no installer or Desktop shortcut. `./build.sh` builds the standalone CLI independently. Neither build command installs apps, enables extensions, moves mail, or changes private settings. `outputs/` and `.build/` are excluded from Git.

Every native Xcode build regenerates the registered Word documents through a shared documentation target; the standalone CLI build script does so before SwiftPM compilation. Python 3 and successful conversion are required. Packaging inherits document generation through `./MacApp/build.sh`; use `python3 docs/build-docx.py` directly for documentation-only updates.

See [native app engineering notes](MacApp/README.md) for architecture, storage, migration, tests, Developer ID signing and notarization. Local builds require no developer membership; they are not notarized public releases. Use temporary fixtures for automated checks and verify real installation, Mail callbacks, restoration, compatible upgrades and removal in a normal macOS session before distribution. The retired Probe app is not required; keep any earlier filtering extension and timer disabled when testing the native extension. The shared MIME, configuration, queue and recovery helpers now live in `MacApp/Shared/`, with all their synthetic checks included in `./MacApp/test.sh`.

## Installer-managed command-line access

The clickable installer offers **Add command-line tool to PATH**, selected by default. Checking it adds `/etc/paths.d/org.mail-filter.command-line`, containing the dedicated directory `/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin`. Open a new Terminal window for macOS to refresh PATH. No personal shell files are edited and no existing directories are removed from PATH.

Unchecking the option on a reinstall removes that exact installer-managed entry, leaving the app and its private settings intact. An existing unrelated file or symlink at the same path is rejected rather than overwritten or removed. The uninstaller validates and removes the same owned entry together with the installed apps, through macOS's authorized file operation.

The app bundle retains the CLI for direct engineering use even when the PATH option is off. The installed launcher loads its own generic prompt files and still uses `~/.config/mail-filter/accounts.txt` and `~/.local/state/mail-filter/processed.json`. Configure the private account file before a live Inbox run. Custom prompts should be outside the signed app bundle and passed with `--prompt` / `--evidence-terms`; changing saved app settings does not change CLI settings.

An independently configured development launcher such as `~/.local/bin/mail-filter` remains unchanged and may take precedence. When switching to the installed tool, first verify the packaged launcher, then remove only the old Mail-Filter launcher. Remove its dedicated shell PATH block only if no other commands use that directory; preserve unrelated shell configuration. Use `type -a mail-filter` to see which launcher your shell selects. Invoke the installed launcher explicitly when testing the packaged version:

```sh
'/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin/mail-filter' --help
'/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin/mail-filter' --dry-run --verbose
```

The bundled example account list is in `DeveloperTools/config/accounts.example.txt`; copy it to the private account path and edit it before using the installed CLI. Manage the development timer from the checkout using `./scripts/agent.sh`. The app and uninstaller have no timer controls; the clickable installer does not install or enable a timer. Developer documentation is also bundled in `DeveloperTools/README-DEVELOPER.md`.

## Command-line setup

The executable target remains in `Package.swift` and `Sources/MailFilter/`. Build it separately:

```sh
./build.sh
.build/release/mail-filter --help
.build/release/mail-filter --fixture fixtures/sample.json --verbose
```

Fixtures never move real mail. For development against an Inbox, explicitly use `--dry-run`; a normal run permits Junk moves. Avoid running apply-mode CLI or timer scans alongside the native extension: their protection records are separate, and native restored-message protection is not copied back to the CLI.

The following optional launcher makes `mail-filter` available from other directories. It uses the conventional checkout location; adjust `MAIL_FILTER_ROOT` for a different checkout. Preserve an existing launcher instead of replacing it unnecessarily.

```sh
mkdir -p ~/.local/bin
cat > ~/.local/bin/mail-filter <<'SH'
#!/bin/zsh
set -eu
export MAIL_FILTER_ROOT="$HOME/Documents/GitHub/Mail-Filter"
exec "$MAIL_FILTER_ROOT/.build/release/mail-filter" "$@"
SH
chmod 755 ~/.local/bin/mail-filter
```

Add this line to `~/.zshrc` if it is not already present, then reload your shell configuration:

```sh
export PATH="$HOME/.local/bin:$PATH"
source ~/.zshrc
```

The CLI's account file and prompt files are independent of the app's saved settings. Configure the private account file below before attempting a real Inbox run. Do not commit personal account lists, message dumps or protection state.

**Normal runs move positive matches to Junk.** Use `--dry-run` to preview without moving. This default was explicitly selected after initial dry-run testing.

## Run from anywhere

```sh
mail-filter
mail-filter --dry-run
mail-filter --verbose
mail-filter --dry-run --verbose
```

Plain `mail-filter` scans the configured accounts, processes up to **30 emails total**, classifies them, and moves positive matches to their account's existing `Junk` mailbox. `--verbose` shows all results and progress; it does not disable moving. Default output shows successful moves, errors, and the final summary. Dry-run output shows positive candidates and a summary confirming zero moves.

If you choose the optional development launcher above, it lives at `~/.local/bin/mail-filter`. After adding its directory to PATH, load the configuration once in an existing Terminal:

```sh
source ~/.zshrc
```

The development launcher loads prompt files from the checkout; the installed launcher loads its bundled defaults. Both use the private account list at `~/.config/mail-filter/accounts.txt`, regardless of your current directory. Explicit relative file arguments are relative to your current directory. Rebuilding the project updates the executable used by the launcher. If you move the project, update the launcher's `MAIL_FILTER_ROOT` path.

## Choose accounts and batch size

Keep your real account names in `~/.config/mail-filter/accounts.txt`, outside the repository. Set it up once:

```sh
mkdir -p ~/.config/mail-filter
chmod 700 ~/.config/mail-filter
cp config/accounts.example.txt ~/.config/mail-filter/accounts.txt
chmod 600 ~/.config/mail-filter/accounts.txt
```

Edit the copied private file before running the tool: one exact Mail account name per line. The published example contains only a fictional account. A missing private file stops processing with setup instructions; the tool never falls back to the example. `config/accounts.txt` and `config/accounts.local.txt` are ignored by Git as an additional safeguard. Blank lines and lines beginning with `#` are ignored. Set this file to the account names you want to scan. The commands below use the fictional account name `example.org`; replace it with your exact Mail account name. Adding/uncommenting an account enables scanning; commenting it disables scanning. No rebuild is needed.

```sh
mail-filter --list-accounts
mail-filter --show-config
mail-filter --account 'example.org' --limit 2 --dry-run
mail-filter --limit 50
```

`--account` overrides the list for one run. `--accounts-file PATH` selects another list. The default is 30 messages; the hard maximum is 50 across the selected accounts in file order. Messages are fetched by index directly from each selected account's `INBOX`, without loading the combined Inbox. Mail typically exposes newer messages first but does not guarantee chronological order. Deleted messages are skipped and count toward the inspected limit.

An empty/missing account list or unmatched account stops processing; there is no fallback to scanning all accounts. Configured names are checked before message retrieval. Each retrieval Apple event has a 20-second timeout. Open Mail and allow syncing to finish if retrieval times out.

## Filtering rules and evidence

Edit `prompts/filter.txt`. Political terms used to verify positive evidence are in `prompts/political-evidence.txt`. Changes apply on the next run without rebuilding. Override with `--prompt PATH` or `--evidence-terms PATH`.

Model classifications are `political` / `not-political`. Operational failures are reported as `review` and leave the message untouched; that status is not a political classification. Marketing links, social media links, unsubscribe notices and urgent donation language alone do not establish politics.

A positive requires verifiable political evidence from the supplied subject/body. Quotes tolerate whitespace, capitalization, invisible formatting, and smart-quote differences. If the model's quote is missing or incorrect but the actual subject contains a configured political term, the subject can serve as evidence. Otherwise the tool searches the supplied body excerpt for an exact sentence or bounded passage containing a configured political term. This fallback still requires a positive model classification; it cannot turn a negative classification into a positive or use text beyond the first 6,000 characters. A term alone never triggers moving: the model must also classify the message as political. Positive reports include the evidence. This conservative check can miss euphemisms or names absent from the term list and does not guarantee perfect classification.

The classifier uses Apple's documented `permissiveContentTransformations` mode with plain-text responses and strict JSON validation. Structured generation would still use default guardrails. Refusals, unknown decisions/fields, malformed output and model errors leave messages in place. A single enclosing Markdown JSON fence is accepted. Each email gets a fresh session; email fields are treated as untrusted data.

## Protected messages and long bodies

Messages from any address configured in Mail are kept without model classification, even if that account is disabled for scanning. This protects notes sent between different personal accounts. Other inboxes remain untouched unless enabled. Address comparison does not authenticate senders.

Empty or invisible-only bodies are kept. Missing message identity or oversized headers are left for review. Bodies over 6,000 characters are classified using their first 6,000 characters and may be moved if the excerpt supports a positive. Positive reports include `bodyTruncated: true` for excerpted messages. Attachments and later body content are not inspected.

Before moving, the tool rechecks account, numeric message ID, RFC message ID, sender, subject, Inbox presence, and classified body text. For long messages it compares the same excerpt, permitting changes beyond it. These are best-effort checks, not an atomic transaction with Mail.

## Junk destination and recovery

The destination must be an existing uniquely named root mailbox on the selected account. The default is `Junk`; use `--junk-mailbox 'actual name'` if Mail uses a different server-side name. The tool does not guess or create mailboxes.

The operation moves messages into the folder; it does not train Mail's junk filter or change global settings. Mail-Filter never empties Junk or permanently deletes mail. Mail/provider retention settings may later delete messages from Junk. Recover a false positive by moving it back to Inbox in Mail.

Legacy explicit apply syntax remains available:

```sh
mail-filter --apply --confirm-junk
```

`--apply` conflicts with `--dry-run`. Do not combine apply flags with diagnostics or fixtures.

## Read-only diagnostics

```sh
mail-filter --check
mail-filter --check-scripts
mail-filter --show-config
mail-filter --list-accounts
mail-filter --account 'example.org' --inspect-message 632553
```

These commands never move mail. Inspection reports body length, a bounded preview, character codes, and personal-note protection. Preview content may be private. `mailBodyLength` over 6,000 identifies a long message; `previewTruncated` refers to the shorter diagnostic preview.

## Build and test

Requirements: macOS 26+, a Mac supporting Apple Intelligence with the model downloaded/enabled, and Swift 6.2+ from Xcode or compatible Command Line Tools. Mail must be configured, and your terminal must have permission to control it under System Settings → Privacy & Security → Automation. No API key or cloud AI service is used; Mail continues its ordinary provider syncing.

```sh
cd ~/Documents/GitHub/Mail-Filter
./build.sh
./test.sh
mail-filter --fixture fixtures/sample.json --verbose
mail-filter --fixture fixtures/sample.json --debug-model
mail-filter --fixture fixtures/political-merchandise.json --verbose
```

Fixture runs always classify synthetic messages without accessing or moving real mail. `--debug-model` shows escaped raw model responses only with fixtures. The script check compiles automation without executing it. Tests include personal-note protection, account selection, political evidence, output controls, long excerpts, and diagnostic/default-mode safeguards.

Exit codes: `0` completed, `1` setup/argument/automation failure, `2` one or more per-message processing failures. Failed moves are reported as unconfirmed; inspect Mail instead of assuming rollback. Summary counts include kept, protected, reviewed and failed messages as processed; only confirmed moves count as moved.

By default each run revisits the current batch. `--skip-processed` remembers successfully kept messages as hashes in `~/.local/state/mail-filter/processed.json`; dry-run political matches are retried when moving is enabled. Before an actual move attempt, a separate identity hash is saved so that the same message returned to Inbox is always protected, including during manual runs and after rule changes. This uses the account ID and RFC message ID, tolerating changes to Mail’s numeric ID. Unconfirmed move attempts also remain protected to avoid repeated moves after a crash. Messages moved before this feature was installed cannot be recognized. Changes to message fields, prompt text or evidence terms invalidate kept-message entries, but do not remove returned-message protection. The state contains no message bodies and uses a lock to prevent overlapping runs sharing that state. It still inspects only the latest configured batch; it does not search older mail beyond the 50-message cap. Swift Package Manager and embedded AppleScript via `NSAppleScript` are used, without third-party dependencies. Build output is ignored under `.build/`.

The public [GitHub repository](https://github.com/keithholt/Mail-Filter) hosts this project. Apple documentation: [Foundation Models](https://developer.apple.com/documentation/foundationmodels) and [content transformation guardrails](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output).


## Run periodically in the background

The LaunchAgent runs every 15 minutes while you are logged in and the Mac is awake. It uses your private account file, the default 30-message limit, and `--skip-processed`. No open Terminal is needed after installation. Python 3 is required for the installer.

First configure your private `~/.config/mail-filter/accounts.txt` as described above. Keep Mail open and synced for the initial test. Build and install a **dry-run** schedule from your normal Terminal (no `sudo`):

```sh
cd ~/Documents/GitHub/Mail-Filter
./build.sh
./scripts/agent.sh install
./scripts/agent.sh status
./scripts/agent.sh logs
```

Check the logs for a completed run and confirm Mail automation permission and model generation work in the background. Terminal permission alone may not cover the launched executable. If macOS denies access, inspect System Settings → Privacy & Security → Automation; stop the schedule until resolved.

After a successful dry run, enable actual moves:

```sh
./scripts/agent.sh install-apply
```

Both install commands start a run immediately and replace any previously loaded version of this agent. Classification may take several minutes before results appear. The agent also loads at login. It runs a batch and exits between scheduled runs.

Run these commands from the repository directory:

| Command | Effect |
| --- | --- |
| `./scripts/agent.sh status` | Show whether the job is running, its run count and last exit code. |
| `./scripts/agent.sh logs` | Show the latest results and errors. |
| `./scripts/agent.sh stop` | Unload the job for this login session. |
| `./scripts/agent.sh start` | Reload an installed, stopped job and run immediately in its saved mode. |
| `./scripts/agent.sh run` | Request a run now for a loaded job; it does not interrupt a running batch. |
| `./scripts/agent.sh install` | Switch to dry-run scheduling. |
| `./scripts/agent.sh install-apply` | Switch to scheduling actual Junk moves. |

A stopped job returns at the next login because its installed file remains. To uninstall permanently, stop it if loaded, then remove its file:

```sh
./scripts/agent.sh stop
rm ~/Library/LaunchAgents/org.mail-filter.agent.plist
```

The agent file is local and contains absolute paths to your checkout; no personal paths are published. If you move the checkout, stop the old agent and reinstall from the new location. After code updates, stop the agent, run `./build.sh`, and start it again. Prompt/account-list edits apply on the next run without rebuilding. To change the interval, stop the agent, change `StartInterval` (seconds) in the local plist, then start it; reinstalling resets it to 900 seconds.

A status of `not running` with last exit code `0` is normal between batches. Exit codes `1` or `2` require checking the error log. A state-lock error means another run is already processing; retry after it finishes. Successful apply runs log a summary with the actual number moved. Dry runs log `moved 0 (dry run)`; install-apply is required to enable moves.

Private output/error logs are in `~/.local/state/mail-filter/logs/`. They can contain message subjects and reasons; they are not committed. Logs append without automatic rotation. Deleting `processed.json` removes both kept-message state and returned-message protection; preserve it if you have restored false positives. Corrupt or inaccessible state stops processing with an error before any move. Manual runs without `--skip-processed` reclassify kept messages in the current batch, but still protect previously selected Junk messages returned to Inbox.

The political-merchandise fixture checks a synthetic PAC-sponsored solicitation against ordinary patriotic retail marketing and a completed-purchase receipt. Expected classifications are political, not-political, not-political; actual model results require verification on your Mac. Prompt changes invalidate remembered kept results on the next scheduled run, while returned-message protection remains in effect.


## Classify one specific message

```sh
mail-filter --account 'example.org' --message-id 123456 --dry-run
```

`--message-id` reads exactly one message by its numeric Mail ID from that account’s Inbox, independent of the recent-message batch limit. It shows the result and bypasses remembered kept classifications, but preserves protection for returned Junk messages. Remove `--dry-run` to permit a verified positive to move to Junk. A missing or ambiguous message/account returns an error without scanning other messages. `--inspect-message` remains a separate read-only inspection command without AI classification.


## Trigger the background agent from anywhere

```sh
mail-filter --run-now
```

This requests an immediate background run in the installed agent’s saved mode (dry-run or actual moves). A loaded idle agent starts now; an unloaded/stopped agent is loaded again and starts immediately, resuming its 15-minute schedule. If a batch is already running, the command reports that and does not interrupt it or queue another batch. If no agent is installed, it reports setup instructions. Use this option alone; change the saved mode with the installer rather than adding filtering flags. Completion is asynchronous: check `./scripts/agent.sh logs` from the checkout for results. The command does not itself classify or move messages.


## Earlier setups

The timer-based implementation is preserved as tag `v1.0.0`. The compatibility Probe app, its extension and its setup/build scripts have been retired. The current app and CLI build without that project. MIME extraction, filtering policy, callback admission, generation deadlines and recovery helpers are maintained under `MacApp/Shared/`; their checks are under `MacApp/Tests/`.

Use **Export Setup…** and **Import Setup…** to move complete native settings and recovery protection. Import also accepts an explicitly selected data folder containing both `settings.json` and `junk-protection.json`. **Import Protection File…** merges a separately chosen native recovery file. Policy-only experimental snapshots require engineering conversion; the app no longer guesses sibling or retired-container paths. Preserve older private data until migration is verified, and never publish configured bundles or exports.

## Incoming-message diagnostics

Build 6 persists callback receipt, body availability, queue admission, analysis start, model decision and final action as fixed categories. Optional callback counters and opaque 12-character identity digests extend schema-1 activity without resetting earlier totals. Digests correlate stages with the read-only selected-message test; no subjects, addresses or bodies are stored in activity.

Native incoming classification and selected-message diagnostics share validated string-label generation through `PoliticalModel`, with three total attempts, fresh sessions, 20-second attempt deadlines, one/two-second backoff and a 60-second overall deadline. Actual token counting on macOS 26.4+ includes saved instructions and input, with 64 output tokens and 512 framing tokens reserved. Oversized excerpts are split into overlapping sections with opening/footer context; the first 6,000 characters remain covered. Context-limit retries force smaller sections. Earlier systems estimate tokens and use smaller initial sections. Every section must complete for a negative result. Errors and late/cancelled results leave mail untouched. The engineering CLI shares the model interface but has no outer native retry/deadline wrapper.

The deadline returns even if generation ignores cancellation. The generation caller checks cancellation before parsing/recording a late reply. No result can reach recovery reservation after timeout. The serial scheduler is released after exhaustion or timeout so later arrivals proceed. Synthetic retry checks cover recovery, exhaustion, permanent failures, valid negatives, invalid replies, uncooperative operations, overall budgets, cancellation during backoff, queue recovery and metadata privacy. The engineering CLI's generation behavior is separate from the native retry policy.

After an attempted job exhausts its budget or fails permanently, the existing bounded in-process fingerprint cache treats it as terminal for that exact input and settings revision. Duplicate callbacks cannot start another three attempts. A changed input/revision or a new extension process can create a new job; this is not persistent move protection. The preflight model-availability check performs no generation and remains eligible for later callbacks.

Build 9 adds MAGA, candidate/candidates and donation/donations to both shipped evidence lists. On host startup, a locked settings upgrade appends these additions only when the saved list equals the original standard vocabulary. Custom lists, rules, account selection, preview/pause, activity and recovery protection remain intact. The revision changes to prevent an in-flight result under an older policy from requesting Junk. Negative classifications are never promoted by keyword matches.

Failure mapping handles both macOS 26's legacy generation errors and macOS 27's current model, session, generated-content parsing and asset errors. Runtime availability checks preserve macOS 26 compatibility. Synthetic macOS 27 error fixtures verify retry decisions and specific categories without calling the model, so newer permanent failures are not silently treated as generic temporary errors.

The settings app's Activity page can analyze the selected Mail message in read-only mode using the existing policy and evidence checks. It uses the same bounded MIME extractor and model interface as event filtering; the report includes the extracted excerpt to help identify missing content. This test never reserves recovery protection or requests a Mail action. Its visible result is not persisted or included in copied diagnostics.

Diagnostic reports display saved activity immediately. The app collects its own last six hours of unified logs on a background worker, drains output without waiting for EOF, retains only the last 32,000 bytes, and stops its child process after 10 seconds. Clipboard writes are checked; the visible report remains selectable when logs or copying fail. Synthetic checks cover large output, timeouts, inherited stdout, launch/access failures, main-actor responsiveness, and account privacy.

Copied reports include fixed-category activity and the app's own recent unified logs. They do not collect Mail's logs or email content. Access failures remain visible in extension logs even when the shared activity store cannot be written. The actual missed email still requires an installed-app test to distinguish delivery, model and verification problems; synthetic tests do not establish its classification.


Build 11 used guided generation with a two-value decision schema and a brief reason. Build 12 replaces that interface because guided responses do not support permissive transformation guardrails. The application finds verifiable evidence in the actual excerpt after a positive. Model input excludes account names, owned addresses and recovery identities. Selected-message diagnostics extract MIME from Mail's source property, not its rendered content, and attach retained automatic history for that exact RFC identity and display the analyzed excerpt for negatives/failures; this text is separate from content-free application reports. A malformed optional MIME alternative no longer discards a valid sibling, while global size/depth/part limits remain enforced.

The unchanged standard prompt and the standard 21- or 26-word lists are upgraded on host startup to include Second Amendment and abortion advocacy. Custom prompts and vocabularies, account selections, preview/pause and restored-message protection remain intact. No private email fixtures or user account settings are committed. Synthetic checks exercise schema decoding, token-budget partitioning, excerpt coverage and migration; actual model accuracy and MailKit moves still require installed-app tests.


Selected-email JSON exports are explicit support artifacts, written atomically with owner-only permissions to the user’s chosen location. They contain base64 RFC source, the decoded excerpt or extraction failure, current policy (not the complete account inventory), same-identity activity and a matching cached analysis. They do not run inference or make Mail actions. Decode `sourceBase64` to reproduce the MIME extractor; the policy snapshot is current, not necessarily the policy used at original receipt. Shared activity retains 500 bounded events within a 1 MiB file limit; older activity stays readable. Do not commit reports or extracted real emails to this public repository.

## Compare model methods on exported emails

If exported reports show model refusals, run this read-only experiment from a normal Terminal session:

```sh
~/Documents/GitHub/Mail-Filter/MacApp/probe-model.sh
```

It reads `Mail-Filter Diagnostic *.json` exports from Desktop and tests the saved excerpt and policy with the former guided decision/reason interface, guided general decision-only generation, guided content-tagging decision-only generation, and guided content-tagging topic/action extraction. These are historical comparison methods; use `--verify-supported-path` for the current production interface. You can pass explicit export paths instead. Each trial has a 30-second deadline and a fresh session. It never accesses Mail, moves messages, or changes filtering settings. The owner-only Desktop output is `Mail-Filter Model Probe.json`; share that file to compare actual results. Topics/actions are diagnostic experiments, not production decision categories. `--check-schemas` compiles/validates the experiment schemas without inference.

Campaign and Vice President were added to the standard verification vocabulary after exported examples exposed missing campaign/office evidence. Build 13 adds **Paid for by** so a sponsorship disclosure can verify an AI-positive appeal without requiring explicit election or donation wording. Standard 21-, 26-, 28- and 30-term lists can upgrade; custom vocabularies remain untouched. Opening the updated settings app appends missing standard terms and changes the policy revision while preserving accounts, instructions, apply/preview mode, pause state and recovery protection. Verification terms still require a positive model result. A tracking parameter such as `utm_campaign` does not count as the standalone word campaign.

To investigate an all-refusal result, run `MacApp/probe-model.sh --investigate-refusal`. This adds a synthetic ordinary receipt and a synthetic campaign appeal as controls. It compares the supported string-label interface on original and hostname-only link representations with guided decision-only requests and Apple's minimal guided topic-tagging setup with no custom instructions. Email wording, issue names and sponsorship text remain present. This tests whether refusals follow the source content, request instructions or opaque link metadata. It saves `Mail-Filter Model Probe Controls.json` on Desktop and does not change the production classifier.


Build 12 corrects the build-11 regression: Apple's `permissiveContentTransformations` works only with string generation. Guided responses apply default guardrails even with that mode selected (see Apple's [safety documentation](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)). Production now requests one string label, validates the entire answer, distinguishes textual refusals from malformed labels, and extracts positive evidence from the original excerpt. No generated explanation or JSON formatting can block a valid label. The token budget reserves 64 response tokens and 512 framing tokens; there is no output schema in production. Detailed generated refusal text is shown only in explicit selected-email analysis or private model experiments.

`MacApp/probe-model.sh --verify-supported-path` tests the supported string interface against Desktop exports plus synthetic receipt and campaign controls. It saves `Mail-Filter Supported Path.json` and makes no Mail or settings changes. These real model results must be checked before claiming a model behavior fix. The older guided experiments remain developer comparisons, not the production interface.

The controlled Terminal comparison for build 12 classified an exported Second Amendment solicitation as political with verifiable source evidence, kept a synthetic receipt not political, and classified a synthetic campaign appeal as political. Hostname-only link cleanup did not change those results. Guided decision-only requests refused all three, while the minimal guided topic tagger refused both political inputs. This verifies the string interface on these examples, not the accuracy of every incoming message or Mail delivery. No mail was moved during the comparison.

## Unified Xcode development

Open **Mail-Filter.xcodeproj** at the repository root. Its navigator follows the repository folders directly; source files remain in place. Opening the folder rather than the project may load the CLI's Swift package instead. `MacApp/generate-project.py` owns native target membership and generates the checked-in project and shared schemes. Regenerate after adding files; `--check` detects drift.

Use **Mail-Filter Local** for ad hoc app/extension development, **Mail-Filter Local Installer** to create and verify the installer, **Mail-Filter Store** for signed sandboxed Development builds and Store archives, **Mail-Filter Build Check** for unsigned sandboxed compilation, and **mail-filter CLI** for the engineering executable. CLI Run defaults to `--help`. The app schemes automatically build and embed the MailKit extension; it does not need a separate build.

The app and extension use the same targets and source lists across channels. The Local scheme additionally builds native CLI and uninstaller targets. The installer aggregate waits for those dependencies, stages their products, embeds the CLI and generic resources in the staged app, and creates `outputs/Mail-Filter Installer.pkg` plus its Desktop shortcut. It does not launch Installer or recursively start a second native build. `MacApp/build.sh` and `MacApp/store-build.sh` invoke this same root project, with no separate app compile lists.

All native builds regenerate the registered Word documents through a shared documentation target with declared inputs and outputs. The packaging helper alone disables Xcode's script sandbox to write repo outputs and the Desktop shortcut. App Sandbox is independently selected through channel-specific entitlements. Local settings, bundle identities and installed command-line paths remain compatible with the existing direct app.

Signed builds read `MacApp/Build/Signing.local.xcconfig`, copied from the example in that directory. Git ignores the private file. Local uses ad hoc signing, DeveloperID supports direct releases, Development uses isolated sandboxed identifiers, Store uses production sandboxed identifiers, and BuildCheck disables signing. Do not add personal team settings to the generated project. The Store dependency graph and payload exclude the CLI and uninstaller.

The settings sidebar displays the running bundle's `CFBundleShortVersionString` and `CFBundleVersion` on every page; its heading uses `CFBundleDisplayName` to distinguish Development. Their source values are `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` and the channel's display name in `MacApp/Build/`. Increment the build number for a changed installer so it can be distinguished from earlier packages. Rebuilding a Local package does not replace an already uploaded Store build.

`./MacApp/store-build.sh check` creates and verifies an unsigned Store archive with development identities. Signed Development qualification passed on October 19, including App Group sharing, incoming Junk moves, restored-message retention and operation with the settings app closed. Automatic Store archives use development signing; export applies distribution signing. Final Store installation, clean-install/update migration, TestFlight and App Review remain separate qualification steps. See `MacApp/Store/README.md`, the developer getting-started guide and `docs/app-store-deployment-plan.md` for staging instructions and dated evidence.

Build 14 added manual address groups, opened-email analysis, complete private setup archives and bounded supplemental JSON-lines history. Build 15 consolidates native builds without changing filtering policy, settings schemas or restored-message protection. No build command installs a new extension or changes working filter settings.
