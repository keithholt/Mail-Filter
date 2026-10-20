#!/usr/bin/env python3
"""Verify a local App Store export without installing or executing its payload."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve()
packages = list(source.glob('*.pkg')) if source.is_dir() else [source]
assert len(packages) == 1 and packages[0].is_file(), 'Expected one exported App Store package'
package = packages[0]
signature = subprocess.run(['/usr/sbin/pkgutil', '--check-signature', str(package)],
                           capture_output=True, text=True)
assert signature.returncode == 0, 'Installer signature could not be verified'
installer = re.search(r'1\.\s+3rd Party Mac Developer Installer: .+ \(([A-Z0-9]{10})\)', signature.stdout)
assert installer, 'App Store installer certificate required; a direct-download installer is not a Store export'

with tempfile.TemporaryDirectory(prefix='mail-filter-store-export-') as temporary:
    expanded = Path(temporary) / 'expanded'
    subprocess.run(['/usr/sbin/pkgutil', '--expand-full', str(package), str(expanded)], check=True)
    apps = list(expanded.rglob('*.app'))
    assert len(apps) == 1, 'Store package must contain exactly one app'
    assert not any(path.name == 'Scripts' for path in expanded.rglob('*')), 'Custom installer scripts are not allowed'
    subprocess.run([sys.executable, str(Path(__file__).with_name('verify.py')), str(apps[0])], check=True)
    entitlements = plistlib.loads(subprocess.check_output(
        ['/usr/bin/codesign', '-d', '--entitlements', ':-', str(apps[0])], stderr=subprocess.DEVNULL))
    assert entitlements['com.apple.developer.team-identifier'] == installer.group(1), 'App and installer signing teams differ'

print('Verified local App Store package: installer signature, matching team, distribution-signed app/extension, profiles and payload. No installation or upload.')
