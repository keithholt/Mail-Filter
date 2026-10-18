# Store build workflow

The native project is **Mail-Filter.xcodeproj at the repository root**. The same app and embedded MailKit extension targets serve local and Store builds. Their source lists live in `MacApp/generate-project.py`; shell entry points invoke the project rather than compiling a parallel version. Configuration, asset, plist and entitlement files live under `MacApp/Build/`.

## Choose an Xcode scheme

| Scheme | Purpose |
|---|---|
| Mail-Filter Local | Ad hoc app, extension, CLI and uninstaller; no paid team needed. |
| Mail-Filter Local Installer | Build native direct products and package them without a recursive build. |
| Mail-Filter Store | Signed sandboxed Development for Build/Run; Store for Archive. |
| Mail-Filter Build Check | Unsigned sandboxed app/extension compilation; no runnable. |
| mail-filter CLI | Engineering executable; Run defaults to `--help`. |

Open the project explicitly; opening the repository folder may load the separate CLI Swift package. The navigator follows repository folders without moving source files. The host builds and embeds its extension automatically. Automatic component schemes default to Local; normal Store development should use the Store host scheme.

The Local Installer aggregate depends on the app, CLI and uninstaller targets. After native compilation, it stages copies, embeds engineering resources in the direct app, reseals its signature and creates `outputs/Mail-Filter Installer.pkg` plus a Desktop shortcut. It never installs or opens the package. Store schemes have no dependency on the CLI, uninstaller or installer helper, and Store payload checks reject those products.

Every native build regenerates Word documentation through a shared target. The documentation script retains its sandbox with declared inputs and outputs. Only the installer helper disables the build-script sandbox to write package outputs and the Desktop shortcut. Runtime sandboxing is a separate entitlement controlled by the chosen distribution configuration.

## Compile without signing

Select **Mail-Filter Build Check**, choose **My Mac**, and press Command-B. This builds the app and embedded extension without a team or certificates. It uses isolated development identities and has no runnable or archive/profile build. It does not establish runtime sandbox permissions or App Group sharing.

From Terminal:

```sh
./MacApp/test.sh
./MacApp/store-build.sh check
```

The shell check compiles the Store configuration with development identities and signing disabled. It verifies the archive at `.build/store-unsigned.xcarchive` without installing, activating or submitting it. All native configurations use `.build/xcode-derived/`, with products separated by configuration. Xcode records built app paths with Launch Services; keep runtime qualification separate from compilation.

| Configuration | Identity and storage |
|---|---|
| Local | Existing direct identity; ad hoc signing; existing Mail-Filter Local settings directory. |
| DeveloperID | Direct identity; Developer ID signing; existing team-prefixed shared group. |
| BuildCheck | Unsigned Development identity/group; compile only. |
| Development | `org.mail-filter.development`; `group.org.mail-filter.development.shared`. |
| Store | `org.mail-filter.app`; `group.org.mail-filter.shared`. |

Development, BuildCheck and Store compile with `APP_STORE`, which excludes the system-log subprocess collector and direct-installer controls. Store host and extension are sandboxed. Direct host builds retain their current unsandboxed behavior; every extension is sandboxed. Local retains its narrowly scoped home-directory storage exception. Store variants have only their provisioned App Group; no fallback opens working local data.

Confirm identifier availability after enrollment. Register the host, its `.extension` identifier and matching group for each signed sandboxed configuration. The Store host requests user-selected read/write file access and a Mail-targeted Apple Events exception; its extension has neither that exception nor local filesystem exceptions. Development payload checks allow named debug/preview libraries, while Store release checks require the release executable alone.

Run `python3 MacApp/generate-project.py` after changing native source membership or adding public navigator files; `--check` detects drift. Keep private signing settings out of generated files. See [the developer guide](../../docs/dev/getting-started.md) for the full build workflow.

## Signed builds after developer access is available

1. Copy `MacApp/Build/Signing.example.xcconfig` to `MacApp/Build/Signing.local.xcconfig` and set `DEVELOPMENT_TEAM` to the actual ten-character paid developer Team ID. The local file is ignored by Git and applies to both signed targets/configurations. Open `Mail-Filter.xcodeproj`, select the **Mail-Filter Store** scheme, and confirm the resolved team under Signing & Capabilities for both targets. Keep automatic signing enabled and allow Xcode to create/download the matching development profiles. Avoid writing team overrides into the generated project; they would be lost on regeneration. Review the entitlements rather than adding broad exceptions to resolve an error.
2. Set `MAIL_FILTER_TEAM_ID` to the actual ten-character team identifier in Terminal, then run `./MacApp/store-build.sh development`. This creates a separately identified sandboxed development app. Qualify its storage and file panels before enabling its extension. Use an isolated macOS user or designated test setup; never enable both filtering extensions against the same working inbox.
3. Import a private setup export or explicitly select the old data folder containing both `settings.json` and `junk-protection.json`. The import preserves pause/preview, inventory, aliases and selections, merges recovery protection, and waits for **Confirm Imported Setup**. A private `migration-backup.json` holds the previous destination setup. Keep original files and exports until qualification succeeds. A legacy folder missing protection is rejected; export a complete setup from the updated direct app instead.
4. Test full Mail account discovery and selected-message source access, including permission denial, restarts and user-selected export. The desktop count probe established only partial automation feasibility. The manual address and `.eml` paths must remain usable without automation.
5. Configure distribution signing/profiles in Xcode and run `./MacApp/store-build.sh archive`. It preserves any existing archive by refusing to overwrite `outputs/store/Mail-Filter.xcarchive`. The verifier checks signed capabilities, provisioned groups, privacy manifests and payload exclusions. Complete isolated Mail action/update tests before upload.
6. Run `./MacApp/store-build.sh export` to create a local App Store Connect export under `outputs/store/export`, or validate and distribute through Xcode Organizer. Export does not upload. Submission and publication remain explicit publisher actions.

The privacy manifest declares elapsed-time measurement and metadata access within authorized storage and user-selected files. Its current reasons are `35F9.1`, `C617.1` and `3B52.1`. Re-audit them when shipped API use changes. The app has no telemetry or email-upload service. App Store privacy answers must also consider any support process the publisher later adopts.

The Store support path uses bounded private activity and JSON-lines history, with Save Report for user-selected export. It does not invoke `/usr/bin/log`. File history is supplementary: write failures must not change classification or persistent recovery protection. The direct developer build may additionally collect its own unified logs.

See the deployment plan and review preparation in `docs/`. The account, signed runtime, clean-install UI, actual Mail actions, TestFlight and App Review gates are still outstanding.
