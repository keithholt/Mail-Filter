"""Inspect generated bundles without launching them or reading personal files."""
from pathlib import Path
import plistlib
import subprocess
import sys

app, uninstaller = map(Path, sys.argv[1:])
extension = app / 'Contents/PlugIns/Mail-Filter.appex'
products = [(app,'org.mail-filter.app'),(extension,'org.mail-filter.app.extension'),(uninstaller,'org.mail-filter.uninstaller')]
groups = []
modes = []
for path, expected in products:
    with (path/'Contents/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    assert info['CFBundleIdentifier'] == expected
    assert info['LSMinimumSystemVersion'] == '26.0'
    mode = info['MailFilterStorageMode']
    modes.append(mode)
    groups.append(info.get('MailFilterAppGroup'))
    signed = subprocess.check_output(['/usr/bin/codesign','-d','--entitlements',':-',str(path)],stderr=subprocess.DEVNULL)
    entitlements = plistlib.loads(signed)
    if mode == 'app-group':
        assert entitlements['com.apple.security.application-groups'] == [info['MailFilterAppGroup']]
        assert not any('temporary-exception' in key for key in entitlements)
    elif mode == 'local-development':
        assert 'MailFilterAppGroup' not in info
        assert 'com.apple.security.application-groups' not in entitlements
        if path == extension:
            assert entitlements['com.apple.security.temporary-exception.files.home-relative-path.read-write'] == ['/Library/Application Support/Mail-Filter Local/']
    else:
        raise AssertionError('Unsupported storage mode')
    if path == extension: assert entitlements['com.apple.security.app-sandbox'] is True
    binary = path/'Contents/MacOS'/info['CFBundleExecutable']
    assert binary.is_file()
    assert binary.stat().st_mode & 0o111 == 0o111
    for candidate in path.rglob('*'):
        assert candidate.name not in ('configuration.json','settings.json','processed.json','junk-protection.json','accounts.txt','activity.json'), candidate
        if candidate.is_file():
            assert candidate.stat().st_mode & 0o444 == 0o444, candidate
        elif candidate.is_dir():
            assert candidate.stat().st_mode & 0o555 == 0o555, candidate
assert len(set(groups)) == 1
assert len(set(modes)) == 1
dependencies = subprocess.check_output(['/usr/bin/otool','-L',str(extension/'Contents/MacOS/MailFilterExtension')],text=True)
for framework in ('MailKit','AppKit'):
    assert '/'+framework+'.framework/' in dependencies
assert (app/'Contents/Resources/filter.txt').is_file()
assert (app/'Contents/Resources/political-evidence.txt').is_file()
developer = app/'Contents/Resources/DeveloperTools'
for relative in ('bin/mail-filter','libexec/mail-filter'):
    path = developer/relative
    assert path.is_file() and path.stat().st_mode & 0o111 == 0o111
subprocess.run(['/usr/bin/codesign','--verify','--strict',str(developer/'libexec/mail-filter')],check=True)
for relative in ('prompts/filter.txt','prompts/political-evidence.txt','config/accounts.example.txt','README-DEVELOPER.md'):
    assert (developer/relative).is_file()
print('Verified product identities, storage entitlements, framework linkage and absence of personal configuration/state')
