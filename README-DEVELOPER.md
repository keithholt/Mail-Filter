# Mail-Filter developer guide

The native settings app and MailKit extension are the user-facing product. The Swift command-line tool is still maintained for engineering, diagnostics and fixture testing; its timer-based baseline is tagged `v1.0.0`. The native build and installer do not replace or remove it.

## Native app development

Full Xcode with first-launch setup completed, macOS 26+, Apple silicon and Python 3 are required. Build and verify from the checkout:

```sh
./MacApp/test.sh
./MacApp/package.sh
```

Packaging builds the settings app, extension and uninstaller, verifies the installer, and writes `outputs/Mail-Filter Installer.pkg`. It then creates `~/Desktop/Mail-Filter Installer.pkg` as a symbolic-link shortcut to that package. Rebuilding replaces the package at the same location, so the shortcut opens the latest build without retaining a stale copy. An existing unrelated Desktop item is preserved; a warning reports conflicts or denied Desktop access without failing a successfully verified package. If macOS asks, allow the build's Terminal application access to Desktop. The package remains available in `outputs/` if the shortcut cannot be created.

`./MacApp/build.sh` builds the application bundles in `.build/mac-app/`, including a separately compiled CLI and generic developer resources. It creates no installer or Desktop shortcut. `./build.sh` builds the standalone CLI independently. Neither build command installs apps, enables extensions, moves mail, or changes private settings. `outputs/` and `.build/` are excluded from Git.

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

The bundled example account list is in `DeveloperTools/config/accounts.example.txt`; copy it to the private account path and edit it before using the installed CLI. Timer management still requires the development checkout; no timer is installed or enabled by the clickable installer. Developer documentation is also bundled in `DeveloperTools/README-DEVELOPER.md`.

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

The timer-based implementation is preserved as tag `v1.0.0`. The compatibility Probe app, its extension and its setup/build scripts have been retired. The current app and CLI build without that project. MIME extraction, filtering policy, callback admission and recovery helpers are maintained under `MacApp/Shared/`; their checks are under `MacApp/Tests/`.

Earlier private configuration snapshots and restored-message protection remain usable through **Import Previous Setup...** and **Import Protection File...** in the app. The usual earlier snapshot is `.build/mailkit-prototype/configuration.json`; its protection file is under `~/Library/Containers/org.mail-filter.prototype.extension/Data/Library/Application Support/Mail-Filter/junk-protection.json`. These are private data, not source or distribution inputs. Preserve them until migration is verified and never publish a configured older app bundle.
