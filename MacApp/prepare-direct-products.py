#!/usr/bin/env python3
"""Stage Xcode-built direct products and embed the separately built CLI.

No Swift compilation, installation, Mail access or settings changes occur here.
The native project is the sole app/extension/CLI/uninstaller compilation path.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def prepare(products, output, mode, identity):
    if mode not in ('local', 'release'):
        raise ValueError('Expected local or release products')
    if mode == 'local' and identity != '-':
        raise ValueError('Local products require ad hoc signing')
    if mode == 'release' and not identity.startswith('Developer ID Application:'):
        raise ValueError('Release products require Developer ID signing')
    expected_storage = 'local-development' if mode == 'local' else 'app-group'
    # Validate before replacing staged output. Store products cannot be converted
    # into direct products by this packaging-only operation.
    for name in ('Mail-Filter.app', 'Uninstall Mail-Filter.app'):
        info = plistlib.loads((products / name / 'Contents/Info.plist').read_bytes())
        if info.get('MailFilterDistribution') != 'direct' or info.get('MailFilterStorageMode') != expected_storage:
            raise ValueError('Build the direct Local or DeveloperID configuration before packaging')
    if not os.access(products / 'mail-filter', os.X_OK):
        raise ValueError('The native CLI target must be built before packaging')
    output.mkdir(parents=True, exist_ok=True)
    for name in ('Mail-Filter.app', 'Uninstall Mail-Filter.app'):
        target = output / name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(products / name, target, symlinks=True)
    app = output / 'Mail-Filter.app'
    developer = app / 'Contents/Resources/DeveloperTools'
    if developer.exists():
        shutil.rmtree(developer)
    for relative in ('bin', 'libexec', 'prompts', 'config'):
        (developer / relative).mkdir(parents=True, exist_ok=True)
    shutil.copy2(products / 'mail-filter', developer / 'libexec/mail-filter')
    for name in ('filter.txt', 'political-evidence.txt'):
        shutil.copy2(ROOT / 'prompts' / name, developer / 'prompts' / name)
    shutil.copy2(ROOT / 'config/accounts.example.txt', developer / 'config/accounts.example.txt')
    shutil.copy2(ROOT / 'README-DEVELOPER.md', developer / 'README-DEVELOPER.md')
    wrapper = developer / 'bin/mail-filter'
    wrapper.write_text('#!/bin/zsh\nset -eu\nexport MAIL_FILTER_ROOT="${0:A:h:h}"\nexec "$MAIL_FILTER_ROOT/libexec/mail-filter" "$@"\n')
    wrapper.chmod(0o755)
    # Only the staged app seal changes when engineering resources are embedded.
    entitlements = subprocess.check_output(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL)
    entitlement_file = output / 'Host.entitlements'
    entitlement_file.write_bytes(entitlements)
    options = ['--force', '--sign', identity, '--options', 'runtime']
    if mode == 'release':
        options.append('--timestamp')
    subprocess.run(['/usr/bin/codesign', *options, '--entitlements', str(entitlement_file), str(app)], check=True)
    for bundle in (app, output / 'Uninstall Mail-Filter.app'):
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    subprocess.run([sys.executable, str(ROOT / 'MacApp/verify_bundle.py'), str(app), str(output / 'Uninstall Mail-Filter.app')], check=True)


if __name__ == '__main__':
    prepare(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), sys.argv[3], sys.argv[4])
