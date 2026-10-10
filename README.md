# Mail-Filter

Native macOS Swift command-line filtering of Apple Mail using on-device Foundation Models. Editable rules currently identify unsolicited political fundraising, campaign advertising, political advocacy, and political mass polls. Ordinary commercial spam is outside the filter.

**Normal runs move positive matches to Junk.** Use `--dry-run` to preview without moving. This default was explicitly selected after initial dry-run testing.

## Run from anywhere

```sh
mail-filter
mail-filter --dry-run
mail-filter --verbose
mail-filter --dry-run --verbose
```

Plain `mail-filter` scans the configured accounts, processes up to **30 emails total**, classifies them, and moves positive matches to their account's existing `Junk` mailbox. `--verbose` shows all results and progress; it does not disable moving. Default output shows successful moves, errors, and the final summary. Dry-run output shows positive candidates and a summary confirming zero moves.

The launcher is `~/.local/bin/mail-filter`. That directory is added to PATH in `~/.zshrc`; load it once in an existing Terminal:

```sh
source ~/.zshrc
```

Default configuration is loaded from `~/Documents/GitHub/Mail-Filter`, regardless of your current directory. Explicit relative file arguments are relative to your current directory. Rebuilding the project updates the executable used by the launcher. If you move the project, update the launcher's `MAIL_FILTER_ROOT` path.

## Choose accounts and batch size

Edit `config/accounts.txt`: one exact Mail account name per line. Blank lines and lines beginning with `#` are ignored. Initially only `example.org` is enabled. Adding/uncommenting an account enables scanning; commenting it disables scanning. No rebuild is needed.

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

A positive requires verifiable political evidence from the supplied subject/body. Quotes tolerate whitespace, capitalization, invisible formatting, and smart-quote differences. If the model's quote is missing or incorrect but the actual subject contains a configured political term, the subject can serve as evidence. A term alone never triggers moving: the model must also classify the message as political. Positive reports include the evidence. This conservative check can miss euphemisms or names absent from the term list and does not guarantee perfect classification.

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
```

Fixture runs always classify synthetic messages without accessing or moving real mail. `--debug-model` shows escaped raw model responses only with fixtures. The script check compiles automation without executing it. Tests include personal-note protection, account selection, political evidence, output controls, long excerpts, and diagnostic/default-mode safeguards.

Exit codes: `0` completed, `1` setup/argument/automation failure, `2` one or more per-message processing failures. Failed moves are reported as unconfirmed; inspect Mail instead of assuming rollback. Summary counts include kept, protected, reviewed and failed messages as processed; only confirmed moves count as moved.

There is no processed-message database: each run revisits the current batch. No launchd or scheduling setup is included. Swift Package Manager and embedded AppleScript via `NSAppleScript` are used, without third-party dependencies. Build output is ignored under `.build/`.

The public [GitHub repository](https://github.com/keithholt/Mail-Filter) hosts this project. Apple documentation: [Foundation Models](https://developer.apple.com/documentation/foundationmodels) and [content transformation guardrails](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output).
