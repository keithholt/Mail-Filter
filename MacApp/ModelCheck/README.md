# Mail Filter Model Check

This temporary diagnostic app identifies the on-device model selected on a Mac. It is an optional preflight for the [local reproduction plan](../../docs/model-reproduction-plan.md), not another filtering extension. It does not read mail, run classification, change settings, install anything or upload reports. It has no connection to the installed Store or Dev app and uses no App Group.

The recipient needs Apple silicon and macOS 27 or later. Xcode, command-line tools, a repository checkout and developer membership are not required to run the final signed helper. Building it requires Xcode's macOS 27 SDK.

## Status and scope

Portable helper signing and distribution are paused. The investigation is performed on the publisher’s Mac. Do not require a remote beta tester to build tools, collect repeated debugging reports or provide access to his machine. This helper may later support one brief optional beta environment check; it is not a dependency for local reproduction work. No portable release ZIP has been produced.

## Optional use of a future signed helper

1. Unzip **Mail-Filter Model Check.zip** and open **Mail-Filter Model Check.app**. It can remain in Downloads; no installer is needed.
2. Click **Check This Mac**. It reports hardware, OS build, selected model variants, reasoning capability, context sizes, language, locale and Low Power Mode.
3. Use **Copy Report** or **Save Report** and share the result yourself. Nothing is sent automatically. The report excludes host names, serial numbers, accounts and email content, and includes the helper version and source fingerprint.
4. Quit the helper when finished. Removing the app does not affect Mail-Filter.

Only a Developer ID signed, notarized and stapled release ZIP is intended for another Mac. Do not send the local test app, instruct a recipient to remove quarantine attributes, or ask them to bypass Gatekeeper. The environment check does not reproduce the classification failure by itself; it records environment metadata only. It cannot select a model variant or establish the cause of a failure.

## Build a local test

From the repository root:

```sh
python3 MacApp/build-model-check.py --local-test
```

The script regenerates registered engineering documents, compiles the app and shared `ModelEnvironment` collector, applies a sandboxed ad hoc signature and verifies its identity and permission boundary. It writes `outputs/model-check/local-test/Mail-Filter Model Check.app`. This mode creates no distributable ZIP and the app displays a local-test warning. It does not replace `/Applications/Mail-Filter.app` or `~/Applications/Mail-Filter Dev.app`, register a Mail extension, or add a scheme to the shipping build.

The helper is an independent engineering executable, like `ModelProbe.swift`; it is excluded from the Store app's source membership and payload. The normal app's unified Xcode targets are unchanged. Source navigation still includes the helper files. Both preflight entry points share one collector; the CLI continues to use `./MacApp/probe-model.sh --environment`.

## Prepare a portable release

Developer ID Application is a different certificate from Apple Development and App Store distribution signing. Use the publisher's paid developer team. Do not create another signing credential without the publisher's approval. The recipient does not need a development provisioning profile or device registration.

After the certificate/private key exists locally, configure a notarytool Keychain profile in a normal Terminal. For interactive credential entry, run:

```sh
xcrun notarytool store-credentials mail-filter-notary
```

Complete Apple's prompts yourself. Never paste passwords, private keys or app-specific passwords into chat, source control or a command-line argument. If Apple requires creating an app-specific password, the account owner must do that step. Existing valid Keychain credentials may be reused. The script accepts the profile name and never asks for or prints the password.

```sh
export MAIL_FILTER_SIGN_IDENTITY='Developer ID Application: Example (YOURTEAMID)'
export MAIL_FILTER_NOTARY_PROFILE='mail-filter-notary'
python3 MacApp/build-model-check.py --release
```

Release mode requires both variables and has no unsigned fallback. It uses hardened runtime and a secure timestamp, verifies the Developer ID signature and exact sandbox entitlements, submits only the helper binary to Apple, requires Accepted status, staples and validates the ticket, and passes Gatekeeper assessment before creating `outputs/model-check/release/Mail-Filter Model Check.zip` and `SHA256.txt`. There are no email reports in that upload. This is notarization, not submission of a Mail-Filter update for App Store review.

A source app already running from the output location must close before rebuilding. Previous generated app bundles are preserved under the output's `previous/` folder. A failed release never turns the local test app into a distribution package. Keep a successful older release separate from the candidate's notarization result; do not describe an earlier ZIP as a newly notarized build after a failure.

## Qualification record

The local sandboxed build opened and collected a report on the M1 Max. Check, Copy Report and Save Report succeeded. The exported JSON matched the source preflight, identified the helper source fingerprint, and used file mode 0600. Release mode refused missing signing/notarization credentials before building or uploading. No mail, inference or filtering settings were involved.

There is currently no installed Developer ID Application identity on the development Mac. Notarization, stapling, Gatekeeper distribution assessment and a clean recipient-Mac launch are outstanding. A local ad hoc launch is not evidence that a downloaded copy will pass those checks.

[Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) explain the distribution signing and ticket workflow.
