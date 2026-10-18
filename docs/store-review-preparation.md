# Mail Filter Store Review Preparation

This checklist prepares the publisher and engineering team for the first submission. The application is not ready for submission while signing and runtime qualification are outstanding. Complete the deployment plan's release gates before uploading a candidate.

## Publisher information

Apple enrollment is processing. Once approved, confirm the legal seller identity, team identifier, app and group identifier availability, App Store Connect roles and signing assets. The publisher must choose the app's price, territories and EU trader status, accept the required agreements, and supply any applicable tax/banking information. These decisions have not been made by the build scripts.

Provide a stable public support URL, privacy-policy URL and reviewer contact. No placeholder URL or personal email address is embedded in the project. Prepare screenshots of setup, filtering controls and activity using synthetic addresses. Complete age-rating, export-compliance and privacy questionnaires against the final product and actual support process. The current build declares only platform encryption use; confirm the final export-compliance answer if dependencies or services change.

## Proposed product description

Mail-Filter analyzes incoming Apple Mail messages on the Mac using Apple's on-device model and requests Junk moves for verified political solicitations. The user chooses which address groups are filtered, can edit the policy, and can preview decisions without moving mail. Messages from the user's configured own addresses and messages previously selected for Junk are protected against repeated moves.

The Mac must support Apple Intelligence, have the model available, remain awake and run Mail with the extension enabled. The settings app does not need to stay open. Filtering is not guaranteed to be perfectly accurate and does not operate remotely while the Mac is unavailable. User-directed email-file analysis is separate from automatic incoming filtering.

## Privacy policy draft

Mail-Filter reads incoming message data through the enabled Mail extension. Account discovery and selected-message diagnostics request Mail automation only when the user chooses those actions. Manual address entry and opening an email source file provide alternatives. Email analysis runs on the Mac using Apple's Foundation Models framework. The app has no analytics, advertising, account service or background email upload.

Settings include addresses, policy, selected groups and preview/pause preferences. Recovery data records message-identity digests so a restored false positive stays in Inbox. Activity and bounded private log files contain processing categories, timestamps, opaque keys, attempts and sanitized error codes. They exclude subjects, sender addresses and message bodies. These digests can be linkable and are not anonymous. Diagnostic file history is limited to three files of one MiB each; support exports include only the last seven days. The separate activity file keeps aggregate counters and up to 500 recent events. Recovery records do not expire with logs.

Setup exports contain private account settings and recovery records. Detailed email reports include full email source, filtering instructions and same-message processing history. The user explicitly creates these files and decides whether to share them. Removing the app does not automatically delete its separate private data or user-created exports. Publish data removal instructions and explain any publisher-operated support retention before using this draft as the public policy.

This draft requires publisher contact information, the intended support procedure and a stable hosted URL. It is not a published privacy policy or a claim that App Store privacy questionnaires are complete.

## Entitlement justification draft

The host requests the Mail-targeted Apple Events exception to discover account names, identifiers and addresses during explicit setup and to read one selected message's source for user-requested diagnostics. Mail's scripting dictionary provides a compose access group that does not cover these received-message/account operations. The desktop compose-only probe failed a read-only metadata script with privilege error -10004; the targeted exception succeeded for account and selection counts. Full operations still require signed qualification.

Automatic incoming filtering uses public MailKit APIs. The extension does not use Apple Events and requests no Mail automation or broad filesystem exception. Host and extension use their provisioned App Group. The user can finish address-based setup and analyze an `.eml` file without granting Mail automation. Permission denial does not authorize any alternative mailbox action.

## Reproducible reviewer demonstration

Use synthetic accounts and messages. Do not send email to another person or move real mail for a demonstration without their authorization.

1. Confirm Apple Intelligence readiness, launch the signed app, and enter `owner@example.com, alias@example.com` on one line and `other@example.net` on another. Select the first group, enable preview, and save.
2. Open a small `.eml` source file containing a synthetic campaign appeal addressed to `alias@example.com`. Analyze it and save the explicit email report. Repeat with an ordinary purchase receipt and a message from `other@example.net`; record the observed outcomes. Model results require the actual signed system and cannot be assumed from fixture expectations.
3. Export Setup, import it into the designated test destination, and confirm that accounts, aliases, policy and pause/preview choices remain intact. No filtering may resume before Confirm Imported Setup. Verify a protected identity after restart.
4. Explain how to enable the extension in Mail. With a designated test account and authorized synthetic deliveries, verify incoming callbacks and preview outcomes. Then permit one eligible synthetic appeal to request Junk, confirm the mailbox move, restore it and confirm it stays in Inbox on subsequent callbacks.
5. Save the application support report. It should contain sanitized processing history and no email body. Keep detailed email export as a separate, explicit action.

Attach final review notes with the approved build number, supported hardware/OS requirements, extension enablement steps, expected synthetic results, permission explanation, support contact and any limitations found in qualification. Supply the exact tested synthetic `.eml` files privately with the review submission. Naturally arriving political email must not be required for review.
