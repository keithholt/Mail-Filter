# App Store feasibility checks

These helpers exercise synthetic configuration, migration and activity plus isolated ad-hoc signed app variants. They do not install a Mail extension, send or move mail, or read production Mail-Filter settings.

From the repository root:

```sh
python3 MacApp/Feasibility/run.py --offline-only
python3 MacApp/Feasibility/run.py --mail-metadata --synthetic-model
```

The second command builds baseline, sandbox, compose-group and Mail-targeted-exception variants. It reports fixed statuses, error codes and counts in `.build/app-store-feasibility/results.json`. The metadata option asks for no new consent; it reads account/selection counts and selected-source length only if Mail is already visible and automation is authorized. It never prints message source or account addresses. The model option classifies one synthetic appeal with a deadline and does not read real mail.

Use `--all-runtime` from a normal Terminal to attempt every variant after a basic sandbox launch failure. Use `--request-mail-permission` only when you intend to allow macOS to request read-only Mail automation consent; it implies the metadata option. A denied preflight is a recorded result. Do not reset TCC or broaden filesystem permissions to force a pass.

Each helper has an `org.mail-filter.feasibility.*` identity. They contain no MailKit extension and do not replace the installed app. Synthetic storage files are removed by the helper; macOS may retain empty sandbox containers for these test identities. Build outputs stay under `.build/`. No helper claims a real App Group or supplies a provisioning profile.

The runner verifies signatures and entitlement dictionaries, but this cannot establish App Store eligibility. Failed sandbox startup, absent desktop context, a model request failure and missing signing identities are separate limitations. Repeat the decisive scenarios in a properly provisioned sandboxed application and extension before shipping.

The [deployment plan](../../docs/app-store-deployment-plan.md) records observed results, developer requirements and outstanding acceptance gates. Production implementation is outside this feasibility harness.
