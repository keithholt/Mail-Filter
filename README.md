# Mail-Filter

Mail-Filter analyzes incoming Apple Mail messages on your Mac and moves verified political solicitations to Junk. It recognizes political fundraising, campaign advertising, advocacy and political mass polls. Ordinary commercial marketing is outside the filter. AI analysis runs on your Mac using Apple's on-device model.

## Build the installer

To build from source, use macOS 26 or later on an Apple silicon Mac, full Xcode with its first-launch setup completed, and Python 3. Select Xcode as the active Command Line Tools installation in Xcode's Settings, under Locations. From Terminal in this project's folder, run:

```sh
./MacApp/package.sh
```

This builds the app and uninstaller, verifies the package, and creates **outputs/Mail-Filter Installer.pkg** plus a Desktop shortcut to it. Each rebuild updates the same installer. Build products are excluded from Git; the installer is generated locally rather than included in the source repository. For checks and release signing, see [README-DEVELOPER.md](README-DEVELOPER.md).

## Install

Double-click **Mail-Filter Installer.pkg** on your Desktop, or open it from the project's **outputs** folder. Follow macOS Installer, then open **Mail-Filter** from Applications. The installer also adds **Uninstall Mail-Filter** to Applications.

You need macOS 26 or later, an Apple silicon Mac supporting Apple Intelligence, and Apple Intelligence enabled with its model available. No developer account is needed to use the local build. The current local installer is not Developer ID signed or notarized; macOS may require approval before opening it. End users do not need Xcode, Git, Python or Terminal.

The package installs into Applications for all users. Each user's account selections, settings and extension enablement are separate. Installing or updating copies the apps without reading messages or enabling filtering automatically. Compatible settings and protection records survive reinstalls and updates.

## Set up filtering

1. Open Mail and let your accounts finish syncing.
2. Open **Mail-Filter** and click **Read Mail Accounts**. Allow it to control Mail if macOS asks. This reads account names and addresses, not messages.
3. Select the accounts you want filtered and click **Save Settings**. An account such as **example.org** is only an example; select your own accounts in the app.
4. Leave **Preview** off to move verified political messages to Junk. Turn it on and save to test classifications while leaving messages in place.
5. In Mail, open **Settings**, then **Extensions**, and check **Mail-Filter**. Restart Mail if the extension is missing after installation or an update.
6. Keep **Enable filtering** switched **ON** (to the right) for analysis to run. **OFF** pauses it. This switch saves immediately; account, Preview and rule changes require **Save Settings**.

Mail must remain running and your Mac must be awake to process incoming messages. The Mail-Filter settings app can quit; its window does not need to stay open. The extension analyzes new arrivals rather than scanning messages already in your Inbox. Keeping the Mac awake does not require keeping the display on.

If account discovery is denied, open **System Settings**, then **Privacy & Security**, then **Automation**, and allow Mail-Filter to control Mail. The app also shows whether Apple's model is available.

## Change settings and check activity

Use the account checkboxes to choose which inboxes to filter. Messages from your own addresses are protected, including mail sent between different personal accounts. Empty messages stay in place. The filter analyzes the first 6,000 characters of decoded body text; attachments are excluded.

You can edit the filtering instructions and political evidence terms under **Filtering instructions**. Click **Save Settings** afterward. Saved changes apply to subsequent incoming messages without rebuilding or restarting Mail. Changes do not automatically reanalyze older Inbox messages.

Verification words support a positive AI decision; they do not flag messages by themselves. The standard list includes **MAGA**, **candidate/candidates**, and **donation/donations**. Job candidates, charitable donations and other nonpolitical messages remain outside the filter's purpose. Opening the updated app adds these words to an unchanged original standard list; customized verification lists are preserved and can be edited here.

The **Activity** page shows recent decisions, errors, and totals. Its Junk count records actions requested from Mail; check your Junk mailbox to confirm delivery. Activity contains no email subjects, addresses or bodies. If there is no activity, confirm that Mail is running, the extension's checkbox is checked, your account is selected, and **Enable filtering** is ON.

## Diagnose a missed message

On **Activity**, check **Incoming callbacks**, the last callback time, and the sequence from **Mail delivered a callback** through **Analysis started**, the model's decision, and the final action. Callbacks can occur more than once per email while Mail downloads its body. These stages distinguish a missing Mail callback from a model refusal, timeout, nonpolitical decision, or rejected evidence.

For a read-only test, select exactly one email in Mail, open Mail-Filter's **Activity** page, and click **Analyze selected email**. The test uses Mail's displayed message text and your current filtering rules. It shows the model's decision, reason and verified evidence without moving the message or changing its recovery protection. If the test fails, it shows the failing stage and error. An invalid model reply is displayed only in the app, so refusals and formatting failures can be distinguished from Mail-access errors. MailKit's incoming MIME extraction can differ from Mail's displayed text, so this tests model behavior separately from automatic delivery.

Use **Copy diagnostic report** to share the processing stages and recent extension logs. The report appears in the window immediately, while logs are collected in the background for up to 10 seconds. It is copied when collection finishes; if clipboard copying fails, select the displayed report and press **Command-C**, or use **Copy displayed report**. A log-access error or timeout still leaves the activity report available. The report excludes message subjects, addresses and bodies; its opaque diagnostic key connects stages for the same message. The selected-email result appears only in the app and is not included in that report.

Incoming classification gets **up to three total attempts** for temporary generation failures, timeouts or invalid replies. Each attempt uses a fresh model session with a 20-second limit. Retries wait one and then two seconds, within a **60-second overall limit**. Activity shows attempt numbers and error categories/codes. A valid not-political answer finishes immediately. Unsupported language/context, model refusals and unverified positives stay in Inbox without further attempts. After exhaustion or the total deadline, the message stays in place and the queue continues; late results cannot move it. These retries apply to incoming processing, not the separate read-only selected-message test, which has a single 60-second deadline.

After an app update, quit and reopen Mail-Filter and Mail so both run the new build. Open Mail-Filter to load any standard-word-list update, and keep its extension checked in Mail's settings. Existing missed Inbox messages are not automatically reanalyzed by installing an update.

## Recover an incorrectly filtered email

Move the message from Junk back to Inbox in Mail. Mail-Filter remembers messages it selected for Junk and protects those messages from being moved again, including after restarts and rule changes. Preserve its private settings and protection records when updating or reinstalling.

Mail-Filter does not empty Junk or permanently delete messages. Mail and your provider retain their usual Junk-retention settings. Model errors and unverifiable classifications leave messages in place.

## Upgrade from an earlier setup

The former **Mail-Filter Probe** testing app is retired and is not needed. Keep any earlier saved settings and protection records until migration is verified.

1. Disable **Mail-Filter Probe** in Mail's Extensions settings and restart Mail.
2. In Mail-Filter, choose **Import Previous Setup...** and select your previous **configuration.json** or **settings.json**. An old configured app bundle can also be imported if you still have one. This imports settings and available restored-message protection.
3. If the app reports missing protection records and you previously restored incorrectly filtered messages, use **Setup & help**, then **Import Protection File...**, before enabling the new extension.
4. Read/refresh accounts, confirm your selections and save.
5. Enable only **Mail-Filter** in Mail's Extensions settings. Verify incoming filtering and restored-message protection before removing the old app or its data.

Reinstalling or updating this app retains compatible account selections, custom rules, Preview, the saved ON/OFF choice, activity and protection records. A new setup defaults **Enable filtering** to ON. An incompatible or damaged settings file produces an error without overwriting it. If a future version changes where settings are stored, import the previous setup before enabling filtering.

## Pause, resume or uninstall

Turn **Enable filtering** OFF to pause and ON to resume. To disable the extension in Mail, uncheck **Mail-Filter** in Mail's Extensions settings. Closing the settings window does not pause filtering.

Open **Uninstall Mail-Filter** from Applications or from Mail-Filter's menu/Setup & help. It pauses filtering and moves the installed apps to Trash. macOS may ask for permission. Settings and restored-message protection are preserved by default; select **Erase private settings...** only if you want to remove them too. Erasing protection records removes that protection if you reinstall. Email messages and Mail accounts are never removed. Restart Mail if an uninstalled extension still appears.

For build, testing and contributor instructions, see [README-DEVELOPER.md](README-DEVELOPER.md).
