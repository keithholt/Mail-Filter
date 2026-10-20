# Native build configuration

Open `Mail-Filter.xcodeproj` at the repository root. `MacApp/generate-project.py` defines all native targets and generates the checked-in project and shared schemes. Source files remain in their existing repository folders.

Use **Mail-Filter Local** for normal development, **Mail-Filter Local Installer** to create the clickable package, **Mail-Filter Store** for signed sandboxed development and Store archives, **Mail-Filter Build Check** for unsigned sandboxed compilation, or **mail-filter CLI** for engineering work. Build the host to automatically build and embed its MailKit extension.

`Common.xcconfig` holds shared defaults; the five named configurations define signing, identifiers, storage and compilation conditions. Local preserves the installed direct app's identity and private settings path. DeveloperID preserves the direct release group. Development and Store use their separate sandboxed groups. BuildCheck disables signing and never launches an app.

Each named `.xcconfig` applies to all targets built with that configuration. Local and Development explicitly set `COPY_PHASE_STRIP = NO` (Xcode's **Strip Debug Symbols During Copy**) so embedding the already-signed Mail extension does not produce the "not stripping binary because it is signed" warning. Keep this override in the configuration files so project regeneration preserves it. Store and DeveloperID retain their distribution defaults; stripping the linked product is a separate setting.

Keep build-setting changes in these configuration files or the project generator so regeneration preserves them. Xcode's recommended compiler warnings are recorded in `Common.xcconfig`. Do not let a recommended-settings update replace Developer ID signing with an Apple Development identity. The Store configuration intentionally uses automatic development signing for its archive; export re-signs it for App Store distribution. The generator's `--check` compares project and scheme structure using macOS's built-in `plutil` and Python's XML parser; Xcode formatting, redundant file labels, encoding-scan and upgrade-version metadata do not count as build changes. Changes to targets, dependencies, signing settings and scheme actions still require reconciliation.

Copy `Signing.example.xcconfig` to the ignored `Signing.local.xcconfig` to set a private developer team for signed configurations. Local and BuildCheck do not use it. An existing file under the former Store directory belongs here now. Never commit certificates, profiles or personal signing overrides.

Native builds regenerate Word documentation. Direct packaging stages the native app, CLI and uninstaller, embeds engineering resources only in the staged direct app, and reseals the signature before verification. Store schemes exclude these engineering products.

See [Developer Getting Started](../../docs/dev/getting-started.md) for building, testing and packaging; see [Store workflow](../Store/README.md) for signed archive/export steps.
