# Mail Filter Store Review Preparation

This checklist records preparation for the first submission and provides the workflow for future candidates. Signed Development tests and local archive/export validation passed on October 19, 2026. Build 18 processed successfully in App Store Connect, and the publisher reported submitting version 2.1.0 for review that day. Apple approval, final Store runtime and clean-install/update checks remain open.

Create the review candidate from the root `Mail-Filter.xcodeproj` using **Mail-Filter Store → Product → Archive**, or `./MacApp/store-build.sh archive`. Both use the same Store configuration and exclude engineering tools. The Local Installer scheme creates a direct-install test package; use the provisioned Store archive for App Store validation. See [Store build workflow](../MacApp/Store/README.md) for signing and export.

## Publisher information

Paid developer-team access is active, and Development certificates/profiles have been exercised. Confirm the legal seller identity, production identifiers, App Store Connect roles and final distribution assets. The publisher must choose the app's price, territories and EU trader status, accept the required agreements, and supply any applicable tax/banking information. These decisions have not been made by the build scripts.

The current [App Store Connect app record](https://appstoreconnect.apple.com/apps/6824658566/distribution) was created on October 19. Its setup values are shown below; use the existing record for Mail-Filter updates. For a different new app, open **Apps → + → New App** and adapt these fields:

| Field | Value |
|---|---|
| Platforms | macOS |
| Name | Mail-Filter |
| Primary language | English (U.S.) |
| Bundle ID | `org.mail-filter.app` |
| SKU | `Mail-Filter-macOS` |
| User Access | Full Access, unless access should be restricted to specific team members |

For a new record, choose **Create** after reviewing the fields. Record creation does not upload, submit or publish an app. If the production bundle ID is absent, check the selected developer team and its registered identifiers; do not substitute the Development ID. The Account Holder must accept current agreements before record creation. See [Apple's new-app procedure](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

Build 16 includes the approved host copyright notice: "Copyright © 2026 Keith Holt. All rights reserved." The payload verifier rejects a missing or blank notice. This resolves the specific metadata omission found in build 15; App Store Connect must still validate the final submission. See [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).

The public [support page](https://keithholt.github.io/Mail-Filter/support.html) and [privacy policy](https://keithholt.github.io/Mail-Filter/privacy.html) use the publisher-approved contact address. Build 18 links to them from Setup & help. Four screenshots with private account information obscured and a synthetic reviewer demonstration were prepared for the submission. Keep age-rating, export-compliance and privacy answers aligned with the final product and actual support process. The current build declares only platform encryption use; reassess if dependencies or services change.

## Upload validation and replacement packages

The initial build-16 upload failed with App Store error 90362: `Mail-Filter.appex` declared `MailFilterExtension` as its executable, while Apple requires the executable name to match the extension directory basename. Build 17 sets the sandboxed extension executable to `Mail-Filter`, retains its Swift module/principal class, and adds validation and a regression check for this constraint. Local archive/export checks do not establish App Store acceptance. Add the replacement package as a new Transporter item rather than retrying a cached rejected package, select the successfully processed build in App Store Connect, and update the build number in review notes.

Build 18 completed upload processing and was selected for version 2.1.0. The publisher reported completing review submission on October 19. App Review acceptance remains pending. Productivity is the primary category and Utilities the secondary category. Automatic release after approval is selected.

The review notes include this Content Rights clarification: Mail-Filter processes email already received in the user's mailbox, with the user's authorization. It does not provide a third-party content catalog or publish users' messages.

## Submission audit and metadata corrections — October 21, 2026

The portal showed version **2.1.0, build 18** as **Waiting for Review**. Its original package passed the export verifier again, including installer and bundle signatures, matching team/profiles, provisioned App Groups, extension executable naming, privacy manifests, and exclusion of developer tools. This is package validation, not a Store runtime or approval result.

The formal **App Sandbox Information** entry now explains the host's `com.apple.security.temporary-exception.apple-events` array value `com.apple.mail`: explicit account discovery, explicit single-message diagnostics, the compose-only probe failure, the manual alternatives, and how the reviewer can assess the reads. Automatic incoming Junk actions remain MailKit operations without that exception in the extension. Apple requests a Feedback reference when an exception compensates for missing sandbox functionality; keep the actual submitted reference in the review entry, not a draft identifier. See [App Sandbox information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information/).

The reviewer ZIP's README incorrectly identified build 16. Its label was corrected to build 18 and the attachment replaced; the two fictional `.eml` files were unchanged. ZIP integrity, MIME parsing and CRLF line endings were checked. Review notes now name the two files and their expected political/nonpolitical results and explain that file analysis never moves mail. These expectations do not assert a live-model test of the final Store package.

The publisher completed the DSA declaration; App Store Connect then reported regulatory requirements complete. The existing Data Not Collected privacy label, public support/privacy URLs, product requirements and review instructions were checked against the submitted app. These checks do not establish App Review acceptance.

These corrections retain build 18 and its existing review submission. To substitute another binary, Apple requires removing the version from review; resubmission starts the review process over. Keep later development builds separate until a replacement or subsequent release is deliberately chosen. See [Remove a submission from review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/remove-a-submission-from-review/).

Final Store/TestFlight runtime qualification, clean-install and compatible-update checks remain outstanding. Do not treat the earlier signed Development tests or these metadata corrections as completing those checks.

## Proposed product description

Mail-Filter analyzes incoming Apple Mail messages on the Mac using Apple's on-device model and requests Junk moves for verified political solicitations. The user chooses which address groups are filtered, can edit the policy, and can preview decisions without moving mail. Messages from the user's configured own addresses and messages previously selected for Junk are protected against repeated moves.

The Mac must support Apple Intelligence, have the model available, remain awake and run Mail with the extension enabled. The settings app does not need to stay open. Filtering is not guaranteed to be perfectly accurate and does not operate remotely while the Mac is unavailable. User-directed email-file analysis is separate from automatic incoming filtering.

## Privacy policy draft

Mail-Filter reads incoming message data through the enabled Mail extension. Account discovery and selected-message diagnostics request Mail automation only when the user chooses those actions. Manual address entry and opening an email source file provide alternatives. Email analysis runs on the Mac using Apple's Foundation Models framework. The app has no analytics, advertising, account service or background email upload.

Settings include addresses, policy, selected groups and preview/pause preferences. Recovery data records message-identity digests so a restored false positive stays in Inbox. Activity and bounded private log files contain processing categories, timestamps, opaque keys, attempts and sanitized error codes. They exclude subjects, sender addresses and message bodies. These digests can be linkable and are not anonymous. Diagnostic file history is limited to three files of one MiB each; support exports include only the last seven days. The separate activity file keeps aggregate counters and up to 500 recent events. Recovery records do not expire with logs.

Setup exports contain private account settings and recovery records. Detailed email reports include full email source, filtering instructions and same-message processing history. The user explicitly creates these files and decides whether to share them. Removing the app does not automatically delete its separate private data or user-created exports. Publish data removal instructions and explain any publisher-operated support retention before using this draft as the public policy.

This draft requires publisher contact information, the intended support procedure and a stable hosted URL. It is not a published privacy policy or a claim that App Store privacy questionnaires are complete.

## Entitlement justification draft

The host requests the Mail-targeted Apple Events exception to discover account names, identifiers and addresses during explicit setup and to read one selected message's source for user-requested diagnostics. Mail's scripting dictionary provides a compose access group that does not cover these received-message/account operations. The desktop compose-only probe failed a read-only metadata script with privilege error -10004; the targeted exception succeeded. Signed Development account discovery and selected-message analysis subsequently passed. Denial behavior, final Store runtime and App Review entitlement acceptance remain separate checks.

Automatic incoming filtering uses public MailKit APIs. The extension does not use Apple Events and requests no Mail automation or broad filesystem exception. Host and extension use their provisioned App Group. The user can finish address-based setup and analyze an `.eml` file without granting Mail automation. Permission denial does not authorize any alternative mailbox action.

## Reproducible reviewer demonstration

Use synthetic accounts and messages. Do not send email to another person or move real mail for a demonstration without their authorization.

1. Confirm Apple Intelligence readiness, launch the signed app, and enter `owner@example.com, alias@example.com` on one line and `other@example.net` on another. Select the first group, enable preview, and save.
2. Open a small `.eml` source file containing a synthetic campaign appeal addressed to `alias@example.com`. Analyze it and save the explicit email report. Repeat with an ordinary purchase receipt and a message from `other@example.net`; record the observed outcomes. Model results require the actual signed system and cannot be assumed from fixture expectations.
3. Export Setup, import it into the designated test destination, and confirm that accounts, aliases, policy and pause/preview choices remain intact. No filtering may resume before Confirm Imported Setup. Verify a protected identity after restart.
4. Explain how to enable the extension in Mail. With a designated test account and authorized synthetic deliveries, verify incoming callbacks and preview outcomes. Then permit one eligible synthetic appeal to request Junk, confirm the mailbox move, restore it and confirm it stays in Inbox on subsequent callbacks.
5. Save the application support report. It should contain sanitized processing history and no email body. Keep detailed email export as a separate, explicit action.

Attach final review notes with the approved build number, supported hardware/OS requirements, extension enablement steps, expected synthetic results, permission explanation, support contact and any limitations found in qualification. Supply the exact tested synthetic `.eml` files privately with the review submission. Naturally arriving political email must not be required for review.
