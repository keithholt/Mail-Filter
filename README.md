# Mail-Filter

Mail-Filter analyzes incoming Apple Mail messages on your Mac and moves verified political solicitations to Junk by default. It recognizes political fundraising, campaign advertising, advocacy and political mass polls. Ordinary commercial marketing is outside the filter. AI analysis runs on your Mac using Apple's on-device model. Preview is optional and is off for a new setup.

For setup help and contact information, see [Support](https://keithholt.github.io/Mail-Filter/support.html). Read the [Privacy Policy](https://keithholt.github.io/Mail-Filter/privacy.html) for on-device processing, local data and optional exports.

## Install Mail-Filter

Requires macOS 26 or later, an Apple silicon Mac supporting Apple Intelligence, and Apple Intelligence enabled with its on-device model available.

Install **Mail-Filter** from the [Mac App Store](https://apps.apple.com/app/id6824658566). Open it from Applications, configure your accounts, then enable its extension in Mail. Updates preserve compatible settings and restored-message protection. Quit Mail before replacing a loaded extension, then reopen it after the update.

The running app's version and build number appear at the bottom of the sidebar. Mail's **Settings > Extensions** shows the extension name with its build number, so you can compare them.

## Build a separate development installer

For source development beside the Store app, open **Mail-Filter.xcodeproj**, select **Mail-Filter Dev Installer**, and choose **Product > Build** (Command-B). Alternatively, run `./MacApp/package.sh` from the checkout. This requires full Xcode, Python 3, and Apple Development signing with provisioned Dev identifiers and App Group. See [README-DEVELOPER.md](README-DEVELOPER.md) for signing and engineering instructions.

The build creates **outputs/Mail-Filter Dev Installer.pkg** and a Desktop shortcut. Its title and introduction show the exact version and build, for example **Mail-Filter Dev 2.1.1 (build 27)**. The package installs **/Applications/Mail-Filter Dev.app**, preserving **/Applications/Mail-Filter.app** and its Store settings. Both applications can be installed together; their accounts, settings, activity and recovery records are separate. The package does not enable an extension or move mail. Existing compatible Dev settings survive updates.

Quit Mail and Mail-Filter Dev before installing or updating Dev. If you previously staged Dev in your personal **~/Applications** folder, move that old app out of Applications first, preserving its private data. Open the new Dev app from the main Applications folder afterward. Development signing is for registered test Macs; this installer is not a public notarized release.

In Mail Settings, enable **exactly one** of **Mail-Filter** and **Mail-Filter Dev**. To test Dev, uncheck Store, then check Dev; reverse those choices for normal Store filtering. Mail provides independent checkboxes; the app cannot make them mutually exclusive. Leave other filtering tools inactive during a live test.

The legacy **Mail-Filter Local Installer** is a separate direct-distribution build, now explicitly named **Mail-Filter Direct Installer.pkg**. It shares the production identity and refuses to replace a Store installation. Use **Mail-Filter Dev Installer** for development.

## Set up filtering

1. Open Mail and let your accounts finish syncing.
2. Open **Mail-Filter** and click **Read Mail Accounts**. Allow it to control Mail if macOS asks. This reads account names and addresses, not messages. Alternatively, choose **Enter Addresses…** and enter every account you own, including accounts you will not filter. Use one line per account and separate aliases with commas.
3. Select the accounts you want filtered and click **Save Settings**. An account such as **example.org** is only an example; select your own accounts in the app.
4. Keep **Preview without moving messages** **OFF** (the default) to move verified political messages to Junk. Turn it **ON** and save only when you want to test classifications while leaving messages in place.
5. In Mail, open **Settings**, then **Extensions**, and check **Mail-Filter**. Restart Mail if the extension is missing after installation or an update.
6. Keep **Enable filtering** switched **ON** (to the right) for analysis to run. **OFF** pauses it. This switch saves immediately; account, Preview and rule changes require **Save Settings**.

Mail must remain running and your Mac must be awake to process incoming messages. The Mail-Filter settings app can quit; its window does not need to stay open. The extension analyzes new arrivals rather than scanning messages already in your Inbox. Keeping the Mac awake does not require keeping the display on.

If account discovery is denied, you can use **Enter Addresses…**, or open **System Settings**, then **Privacy & Security**, then **Automation**, and allow Mail-Filter to control Mail. The app also shows whether Apple's model is available.

## Change settings and check activity

Use the account checkboxes to choose which inboxes to filter. Messages from your own addresses are protected, including mail sent between different personal accounts. Empty messages stay in place. The filter analyzes the first 6,000 characters of decoded body text; attachments are excluded.

After adding or deleting an account in Mail, click **Refresh Accounts**, review the list, then **Save Settings**. Refresh replaces the list with Mail's current accounts and aliases; removed accounts are not kept as manual entries. Existing account selections are retained. Add any extra addresses with **Enter Addresses…** after refreshing. Saving updates own-sender protection to match the displayed addresses; restored-message protection is retained.

You can edit the filtering instructions and political evidence terms under **Filtering instructions**. Click **Save Settings** afterward. Saved changes apply to subsequent incoming messages without rebuilding or restarting Mail. Changes do not automatically reanalyze older Inbox messages.

Verification words support a positive AI decision; they do not flag messages by themselves. The standard verification vocabulary includes **campaign**, **Vice President** and **Paid for by**. Sponsorship wording can verify a political appeal even when it does not explicitly say election or donation. The standard policy explicitly covers unsolicited mass advocacy about the **Second Amendment** and **abortion**, as well as campaign appeals, advertising and political polls. Personal correspondence, medical information, neutral news and ordinary commercial marketing remain protected. Opening an update refreshes only the unchanged standard policy and word list; customized policies remain yours to edit.

The **Activity** page shows recent decisions, errors, totals, and the last recorded extension startup build and time. Startup history does not prove that the process is still running. Application diagnostics also include its process ID; earlier builds have no startup record. Its Junk count records actions requested from Mail; check your Junk mailbox to confirm delivery. Activity contains no email subjects, addresses or bodies. If there is no activity, confirm that Mail is running, the extension's checkbox is checked, your account is selected, and **Enable filtering** is ON.

## Diagnose a missed message

On **Activity**, check **Incoming callbacks**, the last callback time, and the sequence from **Mail delivered a callback** through **Analysis started**, the model's decision, and the final action. Callbacks can occur more than once per email while Mail downloads its body. These stages distinguish a missing Mail callback from a model refusal, timeout, nonpolitical decision, or rejected evidence.

For a read-only test, select exactly one email in Mail, open Mail-Filter's **Activity** page, and click **Analyze selected email** in the **Selected email analysis** panel. It uses the same MIME body extractor and model interface as incoming filtering. It connects the original automatic processing history to the current decision, reason and verified evidence without moving the message or changing its recovery protection. Negative results and failures also show the extracted body excerpt so missing content can be identified. **Copy analysis result** copies this selected-email result, which can contain email content.

You can also choose **Open Email File…** to analyze a saved `.eml` file without Mail automation. This never moves a message. Recipient matching may be incomplete for aliases or Bcc; it is shown only as a diagnostic. **Export opened email report…** saves the file's private source and analysis separately from the application support report.

To report a problematic email, select it in Mail and click **Export selected email report…**. Save the JSON file and attach it to the support conversation. No analysis run is required first. It includes that one email’s full source, extracted body, current policy, diagnostic key, retained automatic history and any matching read-only result. This export contains email content; ordinary application reports do not. It does not move the email or include your account inventory. Activity retains up to 500 recent events; older history may no longer be available.

The separate **Application diagnostics** panel has **Copy diagnostic report** for overall app status and private processing history. This report excludes selected-email analysis, subjects, addresses and bodies. Collection runs in the background; **Copy displayed report** copies the displayed status/history and **Save Report…** saves it to a location you choose. Its opaque keys connect stages for the same message. Supplemental history uses at most three 1 MiB files and reports events within seven days. The direct developer build may additionally collect recent extension logs, with a ten-second limit.

Classification uses Apple's supported permissive **string-response** mode and requests only `political` or `not-political`. The application validates that label and, when your keyword list is populated, separately verifies source evidence before moving a positive. In **Filtering instructions**, leave **Political evidence terms** empty to disable keyword validation and use the AI decision alone. This does not bypass Preview, account selection, own-sender protection or restored-message protection. **Restore defaults** resets both the prompt and keyword editors to the bundled defaults; click **Save Settings** to apply them. Account choices and recovery records are preserved.

The first **6,000 body characters** remain the input limit. Requests begin with sections of at most 3,000 characters, retain opening/footer context and reserve output headroom. Actual token counting is available on macOS 26.4 or later; older systems use smaller sections and estimated counts. A negative requires every section to complete; errors leave mail in place.

Both incoming analysis and the read-only test allow **up to three total attempts**, fresh sessions, a 20-second attempt limit, one/two-second backoff and a **60-second overall deadline**. A context-limit retry reduces section sizes. Temporary generation failures, decoding errors and timeouts can retry. A valid negative, refusal, unsupported request or unverifiable positive stays in Inbox without repeating it. Instructions that alone exceed the available budget require shortening. After exhaustion or the overall deadline, processing continues with the next email; cancelled or late results cannot move mail.

Quit Mail-Filter and Mail **before** installing an app update, then reopen both after installation. Replacing a loaded extension can leave Mail unable to start the replacement even though its checkbox remains checked. Open Mail-Filter to load any standard-policy update, and keep its extension checked in Mail's settings. Existing missed Inbox messages are not automatically reanalyzed by installing an update.

## Recover an incorrectly filtered email

Move the message from Junk back to Inbox in Mail. Mail-Filter remembers messages it selected for Junk and protects those messages from being moved again, including after restarts and rule changes. Preserve its private settings and protection records when updating or reinstalling.

Mail-Filter does not empty Junk or permanently delete messages. Mail and your provider retain their usual Junk-retention settings. Model errors and unverifiable classifications leave messages in place.

## Move settings between installations

Use **Export Setup…** to save your account selections, aliases, custom policy, Preview and ON/OFF preferences, together with restored-message protection. This file contains private account information; keep it secure.

In the destination installation, choose **Import Setup…** and select the export. You can also explicitly select an earlier data folder containing both **settings.json** and **junk-protection.json**. Missing or damaged protection prevents that folder import. Source files remain untouched, existing destination protection is retained, and a private destination backup is created.

Review the imported preferences and click **Confirm Imported Setup** before filtering can resume. Confirmation preserves the imported ON/OFF choice. Keep original data and exports until incoming filtering and restored-message protection have been verified. Enable only one filtering extension during a transition.

Reinstalling or updating this app retains compatible account selections, custom rules, Preview, the saved ON/OFF choice, activity and protection records. A new setup defaults **Enable filtering** to **ON** and **Preview without moving messages** to **OFF**. A previously saved Preview choice is preserved during updates. An incompatible or damaged settings file produces an error without overwriting it. If a future version changes where settings are stored, import the previous setup before enabling filtering.

## Pause, resume or uninstall

Turn **Enable filtering** OFF to pause and ON to resume. To disable the extension in Mail, uncheck **Mail-Filter** in Mail's Extensions settings. Closing the settings window does not pause filtering.

To remove the Store or Dev app, disable that extension in Mail, quit Mail and the corresponding settings app, then move **Mail-Filter.app** or **Mail-Filter Dev.app** from Applications to Trash. Keep the other app if you still use it. App settings and restored-message protection remain available for a reinstall; email messages and Mail accounts are not removed. Restart Mail if an uninstalled extension still appears. The **Uninstall Mail-Filter** helper belongs only to the legacy direct distribution and is not part of Store or Dev.

For build, testing and contributor instructions, see [README-DEVELOPER.md](README-DEVELOPER.md). The [developer documentation](docs/README.md) includes architecture and getting-started guides in Markdown and Word.
