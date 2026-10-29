# Mail-Filter native app engineering notes — version 2

Mail-Filter is a settings app with an embedded MailKit extension. New messages for selected addresses are classified on the Mac using Foundation Models. Verified political solicitations move to Junk by default; ordinary commercial marketing is outside the filter. Preview is optional. The **Enable filtering** switch turns analysis on or off. The settings window can close and the app can quit: Mail hosts the extension independently.

The CLI/timer baseline remains available and is tagged `v1.0.0`. The earlier compatibility Probe is retired. Shared filtering helpers are maintained in `MacApp/Shared/`; neither the app nor the CLI requires a separate Probe app. Building does not install apps or enable a timer.

## Install the separate Dev app

Use **Mail-Filter Dev Installer** in Xcode or run `./MacApp/package.sh`. The verified package and Desktop shortcut are **Mail-Filter Dev Installer.pkg**. Its title and welcome page show the version and build. It installs `/Applications/Mail-Filter Dev.app` with separate identifiers and App Group; the Store app remains `/Applications/Mail-Filter.app`. Dev signing requires provisioned development capabilities and a registered test Mac. Compatible Dev settings are preserved. Enable exactly one of Store and Dev in Mail; Apple owns the independent checkboxes.

The optional engineering CLI installs outside both app bundles under `/Library/Application Support/Mail-Filter Dev/DeveloperTools`. It has an independently owned PATH component and independent CLI settings. Neither package installation nor building activates an extension.

The following direct-distribution notes apply only to the explicitly selected legacy Local/DeveloperID channel, not the separate Dev app.

## Legacy direct installer

Open **outputs/Mail-Filter Direct Installer.pkg** in the project folder and follow macOS Installer. It installs these two apps in Applications:

- **Mail-Filter.app** — account selection, settings, setup help and recent activity.
- **Uninstall Mail-Filter.app** — removal and optional private-data cleanup.

Requirements: macOS 26 or later on an Apple Intelligence-capable Mac, Apple Intelligence enabled, and the on-device model available. The installer accepts Apple silicon Macs and checks the OS version. Model readiness is checked in the settings app. End users do not need Xcode, Python, Git or Terminal.

The local test package is ad-hoc signed and is **not** Developer ID signed or notarized. It requires no developer account or paid membership. It uses a private local settings folder; the sandboxed extension has a file-access entitlement limited to that folder. It does not request the unauthorised `group.org.mail-filter.shared` App Group used by the initial build. A downloaded local package may be blocked by Gatekeeper. The release process below prepares Apple-signed distribution after certificates are available; do not describe the local package as a notarized public release.

The main installer component copies application bundles. Optional command-line components add or remove only the dedicated system PATH entry described in [README-DEVELOPER.md](../README-DEVELOPER.md). They never edit user shell files, read mail/account settings, create per-user configuration as root, or start a timer. The command-line tool and generic resources are bundled for engineering use. Applications are installed at fixed paths rather than updating a development checkout through Installer relocation.

Only installation for all users into `/Applications` is supported by this package. Account choices, extension enablement and private data are per user. Apple's Installer may still display unavailable destination options; its documented package options do not include a switch specifically to hide those entries.

## First launch

1. Open **Mail-Filter** from Applications.
2. Click **Read Mail Accounts**, or choose **Enter Addresses…** and enter all your own account addresses and aliases. Automatic discovery requires Mail to be open and Automation permission; it reads account metadata, not messages.
3. Select the accounts to filter and click **Save Settings**. The default permits verified political messages to move to Junk. Enable Preview before saving to leave messages in place instead.
4. In **Mail → Settings → Extensions**, check **Mail-Filter**. This is a manual user choice; the installer does not enable it silently. Restart Mail after installing/updating if the extension is not listed.
5. Leave Mail running and the Mac awake. You can close Mail-Filter's settings window; closing its last window quits the settings app without stopping the extension.

If the initial build reported a permission error saving `Mail-Filter` under `group.org.mail-filter.shared`, close the settings app, install the updated local package (bundle build 2 or later), and reopen it. Restart Mail to reload the updated extension. Keep filtering disabled until setup succeeds; import any earlier settings and protection records as described below. No existing group-container data is deleted. If you saved settings in that earlier container, import its `settings.json` and protection before enabling the updated extension.

The Activity page shows recent decisions, processing errors, the number classified and the number of Junk actions requested. A request is not a confirmed move: check the Junk mailbox for actual results. No activity yet does not prove the extension is enabled; check Mail's checkbox. The app does not scan existing Inbox messages or prevent sleep.

If account discovery is denied, allow **Mail-Filter** under **System Settings → Privacy & Security → Automation → Mail**, then retry. This permission belongs to the app and is separate from a Terminal permission used by the prototype/CLI. The app reports model availability rather than silently attempting classification without a model.

**Refresh Accounts** replaces the displayed inventory with Mail's current accounts, removing deleted accounts and manual addresses absent from Mail. Stable account IDs retain both checked and unchecked choices, including after account renames or alias changes. Address matching maps a prior manual setup to newly discovered Mail accounts. Review selections and click **Save Settings** to apply; extra manual aliases can be entered afterward. Failed discovery leaves the current inventory unchanged. Settings saves rebuild own-sender addresses from the displayed inventory while preserving restored-message protection.

## Import an earlier setup

Use **Export Setup…** in the source installation, then **Import Setup…** in the destination. The current UI accepts a complete setup archive or a selected data folder containing both `settings.json` and `junk-protection.json`. It preserves accounts, aliases, policy, pause/Preview choices and recovery records, merges destination protection, and creates a private destination backup. Review the result and choose **Confirm Imported Setup** before filtering can resume. Confirmation retains the imported ON/OFF preference.

A missing or damaged protection file prevents folder import; preserve the original files and repair or export a complete setup. Raw prototype `configuration.json` files and old app bundles are not current UI import formats. The policy-only compatibility helper remains an engineering API, separate from this complete setup flow. Use **Setup & help → Import Protection File…** for an explicitly selected compatible recovery file.

Keep older extensions disabled during migration. If a development timer was installed, stop it with `./scripts/agent.sh uninstall` from the checkout; the end-user app has no timer controls. The retired prototype's recovery file normally lived at:

```text
~/Library/Containers/org.mail-filter.prototype.extension/Data/Library/Application Support/Mail-Filter/junk-protection.json
```

Settings saves preserve inherited CLI protection already in the native configuration; they do not read the CLI state file implicitly. Native protection is not written back to the CLI. Avoid simultaneous apply-mode CLI/timer runs and native filtering because their live state stores are separate.

## Settings, privacy and recovery

Filtering instructions and political evidence terms can be edited in the app under **Filtering instructions**. Account, mode and rule changes take effect after **Save Settings**, on subsequent callbacks, without rebuilding or restarting Mail. **Enable filtering ON** enables analysis; **OFF** pauses it immediately. This switch saves immediately and does not require **Save Settings**. Before returning a Junk action, the extension rereads settings under a lock; a pause or settings revision change while the model is generating leaves that message in place. An action already returned to Mail cannot be recalled by turning filtering off.

The default rule text ships in `MacApp/Resources/filter.txt` and the evidence vocabulary in `MacApp/Resources/political-evidence.txt`. The CLI's separate `prompts/` files remain its own configuration; changing them does not change a saved native-app policy. The native editable policy lives outside the signed app bundle.

Local builds share the following private folder, scoped to the current macOS user:

```text
~/Library/Application Support/Mail-Filter Local/
    settings.json
    junk-protection.json
    activity.json
```

The app, extension and uninstaller select this explicit local-development storage mode from their signed bundle metadata. The extension stays sandboxed and receives read/write access only to `/Library/Application Support/Mail-Filter Local/` relative to the user's account home. The helper resolves the real account home because the extension's default home is its own sandbox container. This uses Apple's documented [file-access exception entitlement](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html). It is intended for local testing, not App Store distribution.

Developer ID release builds instead share an entitled private App Group, `YOURTEAMID.org.mail-filter.shared`. Their files are in:

```text
~/Library/Group Containers/<app-group-id>/Mail-Filter/
    settings.json
    junk-protection.json
    activity.json
```

Both modes use files with permissions 600 and a directory with permissions 700. Private account names/addresses are saved only in that build's private store, never embedded in the distributed app. Activity stores fixed decisions/categories and timestamps, not subjects, addresses, reasons, evidence quotes or bodies. It retains up to 500 recent events plus persistent counts. Supplemental private history is bounded to three 1 MiB files and a seven-day reporting window; recovery protection does not expire with diagnostic history. Logs use subsystem `org.mail-filter.app` with the same restrictions. Mail continues its normal provider synchronization; AI analysis is on-device. A denied or invalid release App Group stops filtering; it never falls back to the local-development folder.

Before requesting a Junk move, a hash of the RFC Message-ID is saved atomically. Restoring that message to Inbox protects it after restarts, changes to Mail's numeric ID and rule changes. Corrupt, busy, inaccessible or full protection state prevents a Junk action. Failed/unconfirmed requests stay protected. Preserve this file across upgrades and reinstalls. Changing the storage mode or signing team/group changes the storage location; use **Import Setup…** with a complete export or the previous data folder containing settings and protection, then confirm the imported setup before enabling the new build.

Recipient matching uses delivery headers when available, otherwise MailKit's visible recipient information. This approximates account selection; aliases, redirects, shared addresses, Bcc or copies delivered to multiple accounts can be ambiguous. MailKit does not expose the CLI's account identity in this action handler. Senders from every collected own address are protected. Empty bodies, invalid identity, unreadable/unsupported MIME, model errors and unverified political positives stay in place.

The first 6,000 decoded body characters are classified. Attachments are excluded; HTML is converted without loading remote resources. The bounded decoder and safeguards are maintained in `MacApp/Shared/`, and political-evidence verification is shared with the CLI. One generation runs at a time with at most 16 waiting jobs; excess callbacks stay in place. Mail is not guaranteed to retry failures or deliver old messages again. There is no timer fallback.

## Pause, stop and uninstall

- Turn **Enable filtering OFF** to pause future actions; turn it **ON** to resume.
- Uncheck **Mail-Filter** in Mail's Extensions settings to disable event filtering.
- Open **Uninstall Mail-Filter** in Applications, or choose it from the app menu/Setup & help.

The uninstaller first validates the fixed installed-app identities and any installer-managed command-line PATH entry, pauses configured filtering, quits the settings app, and asks macOS to move the apps and that owned entry to Trash using its native file operation. macOS may present file-operation/authorization UI. An error or partial removal is reported; private data is not erased unless app removal succeeded. Finder removal is available if macOS denies the operation.

Private settings, activity and restored-message protection are preserved by default. Explicitly check **Erase private settings…** to delete those app data files. This removes protection if you reinstall. The development timer is managed separately from the checkout. Email messages, Mail accounts, the older probe, its data, the development CLI launcher and source checkout are never removed. The bundled installed CLI is removed with the app, and the installer-managed PATH entry is removed after validation. Open a new Terminal window to refresh PATH. Installer receipts may remain after native Trash removal; they contain no personal configuration and do not prevent reinstalling. Restart Mail if it continues to display an uninstalled extension.

Reinstalling the same build or installing an update replaces only the application bundles. Compatible account selections, custom rules, Preview, the saved ON/OFF state, activity and protection are loaded automatically from their existing private files. A fresh setup defaults **Enable filtering** to **ON**; reinstalling retains your previous choice. The installer does not reset, migrate or erase settings. Unsupported or damaged settings produce an error and stop filtering without overwriting the old file. A future change of storage location requires explicit migration before enabling the new build; the previous files remain intact. Only the uninstaller's explicit data-erasure option removes the active private settings files.

## Build and package locally

Open the root `Mail-Filter.xcodeproj` for native development. Use **Mail-Filter Dev Installer** for the isolated development package; the default `package.sh` selects it. The legacy direct installer refuses Store receipts, Store metadata and unexpected destination identities before replacement. **Mail-Filter Local** builds the direct app, **Mail-Filter Local Installer** packages the native products, and **Mail-Filter Store** selects signed sandboxed development or Store archiving. **Mail-Filter Build Check** compiles the sandboxed product unsigned. All use the same app and extension targets. The separate **mail-filter CLI** scheme runs the engineering executable with `--help` by default. See [Developer Getting Started](../docs/dev/getting-started.md) for the configuration and signing workflow.

Developer requirements: full Xcode selected with first-launch setup completed, macOS 26+, Apple silicon and Python 3. No third-party libraries are used.

```sh
cd ~/Documents/GitHub/Mail-Filter
./MacApp/test.sh
./MacApp/package.sh local
```

In Xcode, choose **Mail-Filter Local Installer**, **My Mac**, then **Product > Build** (Command-B). The Terminal commands above invoke the same root project and packaging steps. Native builds regenerate the Markdown guides as Word documents before compiling.

The package is `outputs/Mail-Filter Direct Installer.pkg` in the project folder. After package verification, the build creates a Desktop shortcut named `Mail-Filter Direct Installer.pkg` pointing to that file, so it opens the latest package after each rebuild. Existing unrelated Desktop items are preserved; a conflict or denied Desktop access produces a warning while leaving the verified package available in `outputs/`. The `outputs/` directory is excluded from Git. Standalone apps and intermediate files are in `.build/`, which is also ignored. `./MacApp/build.sh` invokes the root `Mail-Filter.xcodeproj` targets and stages the apps with the bundled engineering CLI; it does not install/open/enable them or enable the retired extension. The package verification expands the payload into temporary files and checks identities, signatures, public application permissions, fixed destinations, mutually exclusive command-line choices, narrowly scoped PATH scripts and absence of personal settings/state. No test installs a package or moves real mail. Read-only Installer choice queries require a normal macOS session; the execution sandbox may not expose the target volume.

Native checks cover first-run defaults, duplicate-name account selection, hot reload, pause during generation, stale results, preview, persistent recovery, migration, activity limits, corruption, file permissions and bounded uninstall planning using temporary fixtures. The same test script also runs the shared MIME, guard, political-evidence, burst-admission and recovery checks. Live GUI/Automation/shared-container behavior, real Mail moves/restoration and actual installation/removal need testing outside the execution sandbox. Test upgrades and removal on a separate Mac or clean user account before a public release.

## Developer ID release and notarization

An Apple Developer Program membership and valid Developer ID Application/Installer certificates are required for normal direct distribution. The scripts refuse a release build with missing identities/team values. Replace these placeholders with values from your developer account:

```sh
export MAIL_FILTER_TEAM_ID='YOURTEAMID'
export MAIL_FILTER_SIGN_IDENTITY='Developer ID Application: Example Company (YOURTEAMID)'
export MAIL_FILTER_INSTALLER_IDENTITY='Developer ID Installer: Example Company (YOURTEAMID)'
./MacApp/package.sh release
```

Release app, extension and uninstaller use the same team-prefixed group entitlement, without the local-development file exception. The extension is sandboxed; the settings app is not sandboxed and requests Apple Events access for explicit account discovery and selected-email diagnostics. All executables use Hardened Runtime. Release signing includes secure timestamps. The package is signed with Developer ID Installer.

Set up an existing notarytool Keychain profile interactively rather than storing credentials in the repository:

```sh
xcrun notarytool store-credentials mail-filter-notary
export MAIL_FILTER_NOTARY_PROFILE='mail-filter-notary'
./MacApp/notarize.sh
```

The script submits the signed package, waits for notarization, staples and validates the ticket, and asks Gatekeeper to assess the installer. Network access and valid Apple credentials are needed. Notarization has not been performed on the local test package. A successful signed release still requires clean-Mac installation, extension enablement, shared-storage, live classification, upgrade/recovery and uninstall testing before publishing.

Apple references: [app-extension lifecycle](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html), [App Groups and sandbox access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox), [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Mail extension enablement/removal](https://support.apple.com/guide/mail/use-mail-extensions-mlhla9a93cd5/mac).
