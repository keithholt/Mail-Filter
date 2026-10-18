# Native build configuration

Open `Mail-Filter.xcodeproj` at the repository root. `MacApp/generate-project.py` defines all native targets and generates the checked-in project and shared schemes. Source files remain in their existing repository folders.

Use **Mail-Filter Local** for normal development, **Mail-Filter Local Installer** to create the clickable package, **Mail-Filter Store** for signed sandboxed development and Store archives, **Mail-Filter Build Check** for unsigned sandboxed compilation, or **mail-filter CLI** for engineering work. Build the host to automatically build and embed its MailKit extension.

`Common.xcconfig` holds shared defaults; the five named configurations define signing, identifiers, storage and compilation conditions. Local preserves the installed direct app's identity and private settings path. DeveloperID preserves the direct release group. Development and Store use their separate sandboxed groups. BuildCheck disables signing and never launches an app.

Copy `Signing.example.xcconfig` to the ignored `Signing.local.xcconfig` to set a private developer team for signed configurations. Local and BuildCheck do not use it. An existing file under the former Store directory belongs here now. Never commit certificates, profiles or personal signing overrides.

Native builds regenerate Word documentation. Direct packaging stages the native app, CLI and uninstaller, embeds engineering resources only in the staged direct app, and reseals the signature before verification. Store schemes exclude these engineering products.

See [Developer Getting Started](../../docs/dev/getting-started.md) for building, testing and packaging; see [Store workflow](../Store/README.md) for signed archive/export steps.
