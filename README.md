# Mail-Filter

A native macOS Swift command-line tool that classifies Apple Mail inbox messages using Apple's on-device Foundation Models. **Dry-run is the default.** Filtering rules live in an editable text file. The starting rules target unsolicited political campaign and advocacy solicitations; edit them to filter other content.

## Requirements

- macOS 26 or newer on a Mac that supports Apple Intelligence.
- Apple Intelligence enabled in System Settings, with its on-device model downloaded.
- Swift 6.2 or newer (Xcode or compatible Command Line Tools).
- Apple Mail configured and able to download the messages you want to inspect.
- Permission for your terminal to control Mail, granted when macOS asks. If denied, review System Settings → Privacy & Security → Automation.

No API key or cloud AI service is used. The model runs locally. Mail itself may sync with your mail provider as usual.

## Build and start

```sh
cd ~/Documents/GitHub/Mail-Filter
./build.sh
.build/release/mail-filter --help
.build/release/mail-filter --check
```

Check model availability first. This does not open or read Mail. Build artifacts stay under `.build/` and are ignored by Git.

## Test with sample email first

```sh
.build/release/mail-filter --fixture fixtures/sample.json
```

This runs real on-device classification on synthetic messages, without accessing Apple Mail. The samples include a campaign solicitation, personal correspondence, and a receipt containing an attempted instruction override. Model decisions can vary; inspect the reasons before trusting your rules.

```sh
swift test
.build/release/mail-filter --check-scripts
```

The safety tests do not access Mail or the model. The script check only compiles the AppleScript automation, including the move script; it does not execute it.

## Read-only inspection of Mail

```sh
.build/release/mail-filter --list-accounts
.build/release/mail-filter --account 'example.org' --limit 2
```

Use the exact account name shown by `--list-accounts`. Leaving out `--account` reads across the combined Inbox. It inspects at most 10 messages by default (up to 100 with `--limit`), in the order Mail exposes them. Empty inboxes produce zero results. Messages already marked deleted are skipped. Mail permission errors stop the run. Reading does not explicitly mark messages read, flag them, or move them.

Results are JSON lines after a short status header, with account, message ID, subject, decision, reason, and action. Bodies are not logged, but subjects and model explanations can contain private information. If saving output, keep it under the ignored `reports/` directory and protect it appropriately.

## Change the filtering rules

Edit `prompts/filter.txt`, or use a private file outside the repository:

```sh
.build/release/mail-filter --prompt '/absolute/path/to/my-rules.txt' --limit 2
```

The default prompt path is relative to your working directory. Run from the repository root or provide an absolute path. Changes take effect on the next run without rebuilding. The model returns `keep`, `trash`, or `review`; only `trash` is eligible for moving. No fixed political category is hard-coded into the classifier.

Each email gets a fresh model session. Email fields are explicitly treated as untrusted data. This reduces instruction-injection risk but does not make AI classification infallible. Review dry-run output against representative messages whenever changing rules.

## Explicitly move matching messages

After reviewing dry-run results, verify the exact destination mailbox in Mail. The destination must exist uniquely at the selected account's root; the tool does not create mailboxes or guess localized Trash names. You can choose an existing review/quarantine mailbox instead of Trash while validating the filter.

```sh
.build/release/mail-filter --account 'example.org' --limit 2 \
  --apply --confirm-trash --trash-mailbox 'Trash'
```

**This command changes real mail.** It reclassifies the current batch, so it does not apply a previously saved dry-run report. Use small limits initially. Before each move, the tool checks the account, numeric message ID, RFC message ID, sender, subject, full body, and current Inbox presence. Changed or missing messages are not moved. This is a best-effort check rather than an atomic transaction with Mail.

Mail-Filter uses Mail's `move` operation. It never permanently deletes messages or empties Trash. Mail or your provider's own Trash retention settings can later delete trashed messages. Recover mistakes using Mail's move commands before that happens.

## Conservative behavior and limits

- Missing bodies or RFC message IDs, truncated bodies, and oversized headers go to manual review without model classification or moving.
- Bodies longer than 6,000 characters are truncated during retrieval and left untouched. Attachments are not inspected.
- Prompts must contain 1–6,000 characters. The model has a limited context window; even accepted input can exceed it. Model refusals, context errors, and other failures leave mail in place for review.
- A failed move is reported as unconfirmed: inspect Mail rather than assuming it was rolled back.
- Exit codes: `0` completed, `1` setup/argument/automation error, `2` one or more messages need review because processing failed or safety checks rejected them.
- No persistent processed-message database: each invocation inspects the current batch again. Keep/review messages may recur, so this first version is for manual command-line use rather than unattended inbox draining.
- No scheduling or launchd setup is included.

## Implementation

Swift Package Manager executable, Foundation Models guided generation, and embedded AppleScript via `NSAppleScript`. No third-party dependencies. Automation returns typed Apple event lists rather than delimiter-separated email text.

Apple's framework documentation: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), and [generating content](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

## Initial verification on this Mac

- All six safety tests passed using Swift Testing.
- The executable compiled with the installed Command Line Tools.
- Read, account-list, and move AppleScripts compiled without execution. An explicit system Mail application path avoids application-name terminology lookup failures in a restricted environment.
- Foundation Models reported available, but the synthetic-message generation attempt returned `ModelManagerServices.ModelManagerError 1008`. Each message was left for review and the run returned exit code 2. Successful model classification remains to be verified from a normal Terminal session.
- The read-only account-list attempt returned AppleScript error `-10827` while accessing Mail from this environment. Real inbox retrieval and mailbox moves remain unverified. No real mail was deleted or moved.

The local repository is connected to the private [keithholt/Mail-Filter](https://github.com/keithholt/Mail-Filter) repository. Initial code remains local until a push is explicitly approved.
