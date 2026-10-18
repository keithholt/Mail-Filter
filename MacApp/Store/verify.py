#!/usr/bin/env python3
"""Validate a Store payload without launching, registering or submitting it."""
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
unsigned = '--unsigned' in sys.argv
development = '--development' in sys.argv
root = Path(__file__).resolve().parents[1] / 'Build'
identifier = 'org.mail-filter.development' if development else 'org.mail-filter.app'
group = 'group.org.mail-filter.development.shared' if development else 'group.org.mail-filter.shared'
extension = app / 'Contents/PlugIns/Mail-Filter.appex'
assert sorted(p.name for p in (app / 'Contents/PlugIns').iterdir()) == ['Mail-Filter.appex']
for bundle, suffix, template in ((app, '', 'Host'), (extension, '.extension', 'Extension')):
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == identifier + suffix
    assert info['MailFilterDistribution'] == 'app-store'
    assert info['MailFilterStorageMode'] == 'app-group' and info['MailFilterAppGroup'] == group
    assert info['LSMinimumSystemVersion'] == '26.0'
    assert (bundle / 'Contents/MacOS' / info['CFBundleExecutable']).is_file()
    executable_names = {p.name for p in (bundle / 'Contents/MacOS').iterdir()}
    allowed_executables = {info['CFBundleExecutable']}
    if development:
        # Xcode's unoptimized builds may split the executable into a debug
        # dylib and add its SwiftUI preview trampoline. Store payloads must
        # still contain only the release executable.
        allowed_executables |= {info['CFBundleExecutable'] + '.debug.dylib', '__preview.dylib'}
    assert executable_names.issubset(allowed_executables), (bundle, executable_names)
    declared = plistlib.loads((root / (template + '.entitlements')).read_bytes())
    assert declared['com.apple.security.app-sandbox'] is True
    assert declared['com.apple.security.application-groups'] == ['$(MAIL_FILTER_APP_GROUP)']
    assert not any('files.home-relative' in key or 'files.absolute' in key for key in declared)
    if template == 'Host':
        assert declared['com.apple.security.files.user-selected.read-write'] is True
        assert declared['com.apple.security.temporary-exception.apple-events'] == ['com.apple.mail']
    else:
        assert set(declared) == {'com.apple.security.app-sandbox', 'com.apple.security.application-groups'}
    privacy = plistlib.loads((bundle / 'Contents/Resources/PrivacyInfo.xcprivacy').read_bytes())
    assert privacy == plistlib.loads((root / 'PrivacyInfo.xcprivacy').read_bytes())
    if not unsigned:
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(bundle)], check=True)
        signed = plistlib.loads(subprocess.check_output(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
        expected = declared
        expected['com.apple.security.application-groups'] = [group]
        for key, value in expected.items():
            assert signed.get(key) == value, (bundle, key)
        allowed = set(expected) | {'com.apple.application-identifier', 'application-identifier', 'com.apple.developer.team-identifier', 'com.apple.security.get-task-allow'}
        assert set(signed).issubset(allowed), signed
        assert development or not signed.get('com.apple.security.get-task-allow', False)
        profile = plistlib.loads(subprocess.check_output(['/usr/bin/security', 'cms', '-D', '-i', str(bundle / 'Contents/embedded.provisionprofile')]))
        granted = profile['Entitlements']
        assert group in granted['com.apple.security.application-groups']
        assert granted.get('com.apple.application-identifier', granted.get('application-identifier', '')).endswith('.' + identifier + suffix)
    for path in bundle.rglob('*'):
        assert path.name not in {'DeveloperTools', 'settings.json', 'configuration.json', 'accounts.txt', 'processed.json', 'activity.json', 'junk-protection.json', 'migration-backup.json'}, path
        assert path.suffix not in {'.eml', '.pkg'}, path
assert (app / 'Contents/Resources/AppIcon.icns').is_file()
assert (app / 'Contents/Resources/filter.txt').is_file()
assert (app / 'Contents/Resources/political-evidence.txt').is_file()
assert not list(app.rglob('*Uninstall*.app'))
print('Verified Store payload, privacy manifests, isolation and absence of developer tools/private state.' if unsigned else 'Verified Store payload, signed capabilities and provisioned groups.')
if unsigned:
    print('Unsigned compilation only: no runtime, provisioning or App Store acceptance claim.')
