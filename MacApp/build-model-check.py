#!/usr/bin/env python3
"""Build the standalone model preflight; never installs or accesses Mail."""
from pathlib import Path
import argparse
import datetime
import hashlib
import os
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
IDENTIFIER = 'org.mail-filter.model-check'
NAME = 'Mail-Filter Model Check'
SOURCES = [ROOT / 'MacApp/Shared/ModelEnvironment.swift', ROOT / 'MacApp/ModelCheck/ModelCheckApp.swift']


def run(arguments, **kwargs):
    return subprocess.run([str(a) for a in arguments], check=True, **kwargs)


def verify(app, release=False):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != IDENTIFIER or info['ModelCheckLocalTest'] == release:
        raise ValueError('Unexpected helper identity or distribution mode')
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
    entitlements = plistlib.loads(subprocess.check_output(
        ['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
    if entitlements != {'com.apple.security.app-sandbox': True, 'com.apple.security.files.user-selected.read-write': True}:
        raise ValueError('Unexpected helper permissions')
    if (app / 'Contents/PlugIns').exists() or (app / 'Contents/Frameworks').exists():
        raise ValueError('Helper must not contain extensions or extra frameworks')
    details = subprocess.check_output(['/usr/bin/codesign', '-dvvv', str(app)], stderr=subprocess.STDOUT, text=True)
    if release and ('Authority=Developer ID Application:' not in details or 'Timestamp=' not in details or 'runtime' not in details):
        raise ValueError('Developer ID, secure timestamp and hardened runtime are required')
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--local-test', action='store_true', help='Ad hoc app for testing on this Mac only; creates no distributable ZIP')
    mode.add_argument('--release', action='store_true', help='Developer ID sign, notarize, staple and verify a portable ZIP')
    args = parser.parse_args()
    identity = os.environ.get('MAIL_FILTER_SIGN_IDENTITY', '')
    profile = os.environ.get('MAIL_FILTER_NOTARY_PROFILE', '')
    if args.release and (not identity.startswith('Developer ID Application:') or not profile):
        parser.error('Release requires MAIL_FILTER_SIGN_IDENTITY="Developer ID Application: …" and an existing MAIL_FILTER_NOTARY_PROFILE. No unsigned distribution fallback.')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip()
    if int(sdk.split('.')[0]) < 27:
        parser.error('Building this helper requires the macOS 27 SDK; the recipient needs only macOS 27 on Apple silicon.')
    run([sys.executable, ROOT / 'docs/build-docx.py'])
    revision = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        revision += ' modified'
    fingerprint = hashlib.sha256(b'\0'.join(p.read_bytes() for p in SOURCES)).hexdigest()
    destination = ROOT / 'outputs/model-check' / ('release' if args.release else 'local-test')
    destination.mkdir(parents=True, exist_ok=True)
    scratch = ROOT / '.build/model-check'
    scratch.mkdir(parents=True, exist_ok=True)
    app_destination = destination / (NAME + '.app')
    if app_destination.exists():
        if plistlib.loads((app_destination / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != IDENTIFIER:
            raise ValueError('Refusing to replace an unrelated output')
        processes = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
        if str(app_destination) + '/Contents/' in processes:
            raise ValueError('Quit Model Check before rebuilding it')
    with tempfile.TemporaryDirectory(prefix='build-', dir=scratch) as temp:
        app = Path(temp) / (NAME + '.app')
        executable = app / 'Contents/MacOS/ModelCheck'
        resources = app / 'Contents/Resources'
        executable.parent.mkdir(parents=True)
        resources.mkdir(parents=True)
        info = {
            'CFBundleIdentifier': IDENTIFIER, 'CFBundleDisplayName': NAME,
            'CFBundleName': NAME, 'CFBundleExecutable': 'ModelCheck', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
            'LSMinimumSystemVersion': '27.0', 'NSHighResolutionCapable': True,
            'LSApplicationCategoryType': 'public.app-category.developer-tools',
            'NSHumanReadableCopyright': 'Copyright © 2026 Keith Holt. All rights reserved.',
            'ModelCheckSourceRevision': revision, 'ModelCheckSourceSHA256': fingerprint,
            'ModelCheckSDKVersion': sdk,
            'ModelCheckLocalTest': args.local_test, 'CFBundleIconFile': 'AppIcon',
        }
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        (resources / 'AppIcon.icns').write_bytes((ROOT / 'MacApp/Resources/PoliticalAdFilter.icns').read_bytes())
        (resources / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({
            'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [], 'NSPrivacyAccessedAPITypes': []}))
        run(['xcrun', 'swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-target', 'arm64-apple-macos27.0',
             *SOURCES, '-framework', 'AppKit', '-framework', 'SwiftUI', '-o', executable],
            env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(Path(temp) / 'clang-cache')})
        signing = ['/usr/bin/codesign', '--force', '--options', 'runtime', '--sign', identity if args.release else '-',
                   '--entitlements', ROOT / 'MacApp/ModelCheck/ModelCheck.entitlements']
        if args.release:
            signing.append('--timestamp')
        run([*signing, app])
        verify(app, args.release)
        if args.release:
            upload = Path(temp) / 'notary-upload.zip'
            run(['/usr/bin/ditto', '-c', '-k', '--keepParent', app, upload])
            result = run(['xcrun', 'notarytool', 'submit', upload, '--keychain-profile', profile,
                          '--wait', '--output-format', 'plist'], capture_output=True)
            (destination / 'notarization-result.plist').write_bytes(result.stdout)
            if plistlib.loads(result.stdout).get('status') != 'Accepted':
                raise ValueError('Notarization not accepted; no distributable ZIP was created')
            run(['xcrun', 'stapler', 'staple', app])
            run(['xcrun', 'stapler', 'validate', app])
            run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose', app])
        if app_destination.exists():
            backup = destination / 'previous' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            backup.mkdir(parents=True)
            app_destination.rename(backup / app_destination.name)
        run(['/usr/bin/ditto', app, app_destination])
    verify(app_destination, args.release)
    if args.release:
        package = destination / (NAME + '.zip')
        run(['/usr/bin/ditto', '-c', '-k', '--keepParent', app_destination, package])
        (destination / 'SHA256.txt').write_text(hashlib.sha256(package.read_bytes()).hexdigest() + '  ' + package.name + '\n')
        print('Signed, notarized and stapled helper: ' + str(package))
    else:
        print('LOCAL TEST ONLY: ' + str(app_destination))
        print('No distributable ZIP created. Developer ID signing and notarization are still required before sending it.')
    print('No app installed, Mail accessed, inference generated, extension registered or filter settings changed.')


if __name__ == '__main__':
    main()
