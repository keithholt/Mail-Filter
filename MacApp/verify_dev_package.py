#!/usr/bin/env python3
"""Inspect the complete Dev installer without installing it or touching Mail."""
from pathlib import Path
import importlib.util
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='mail-filter-dev-package-check-') as temp:
    root = Path(temp)/'expanded'
    subprocess.run(['/usr/sbin/pkgutil', '--expand-full', sys.argv[1], str(root)], check=True, stdout=subprocess.DEVNULL)
    distribution = ET.parse(root/'Distribution').getroot()
    assert distribution.find('./volume-check/allowed-os-versions/os-version').attrib['min'] == '26.0'
    assert distribution.find('options').attrib['hostArchitectures'] == 'arm64'
    choices = {item.attrib['id']:item for item in distribution.findall('choice')}
    assert set(choices) == {'app', 'commandLine', 'commandLineOff'}
    assert choices['commandLine'].attrib['start_selected'] == 'true'
    assert 'selected' not in choices['commandLine'].attrib
    assert choices['commandLineOff'].attrib['selected'] == '!choices.commandLine.selected'
    ids = ['org.mail-filter.development.installer', 'org.mail-filter.development.command-line.enabled',
           'org.mail-filter.development.command-line.disabled']
    packages = {ET.parse(path).getroot().attrib['identifier']:(path.parent, ET.parse(path).getroot())
                for path in root.rglob('PackageInfo')}
    assert set(packages) == set(ids)
    app, metadata = packages[ids[0]]
    assert metadata.attrib['install-location'] == '/Applications'
    assert {path.name for path in (app/'Payload').iterdir()} == {'Mail-Filter Dev.app'}
    for entry in metadata.findall('bundle'):
        assert entry.attrib.get('relocate') != 'true'
    bundle = app/'Payload/Mail-Filter Dev.app'
    info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'org.mail-filter.development'
    assert info['MailFilterAppGroup'] == 'group.org.mail-filter.development.shared'
    extension = plistlib.loads((bundle/'Contents/PlugIns/Mail-Filter.appex/Contents/Info.plist').read_bytes())
    assert extension['CFBundleIdentifier'] == 'org.mail-filter.development.extension'
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        assert info[key] == extension[key]
    label = f"Mail-Filter Dev {info['CFBundleShortVersionString']} (build {info['CFBundleVersion']})"
    assert distribution.find('title').text == label
    assert label in (root/'Resources/Welcome.html').read_text()
    assert label in (root/'Resources/Finished.html').read_text()
    assert {item.attrib['version'] for _,item in packages.values()} == {info['CFBundleShortVersionString']+'.'+info['CFBundleVersion']}
    assert {item.attrib['id'] for item in distribution.findall("./pkg-ref[@id='"+ids[0]+"']/must-close/app")} == {'com.apple.mail','org.mail-filter.development'}
    assert {path.name for path in (app/'Scripts').iterdir()} == {'preinstall'}
    assert (app/'Scripts/preinstall').read_bytes() == (ROOT/'MacApp/InstallerScripts/Development/preinstall').read_bytes()
    subprocess.run([sys.executable, str(ROOT/'MacApp/Store/verify.py'), str(bundle), '--development'], check=True)
    cli, metadata = packages[ids[1]]
    assert metadata.attrib['install-location'] == '/'
    spec = importlib.util.spec_from_file_location('dev_packaging', ROOT/'MacApp/package-dev.py')
    packaging = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packaging)
    tools = cli/'Payload'/packaging.CLI_ROOT.lstrip('/')
    expected = {tools.relative_to(cli/'Payload').as_posix()+'/'+name for name in (
        'bin/mail-filter', 'libexec/mail-filter', 'prompts/filter.txt', 'prompts/political-evidence.txt',
        'config/accounts.example.txt', 'README-DEVELOPER.md')}
    expected.add('etc/paths.d/'+packaging.PATH_ID)
    assert {path.relative_to(cli/'Payload').as_posix() for path in (cli/'Payload').rglob('*') if path.is_file()} == expected
    assert (cli/'Payload/etc/paths.d'/packaging.PATH_ID).read_text() == packaging.CLI_ROOT+'/bin\n'
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(tools/'libexec/mail-filter')], check=True)
    assert (tools/'bin/mail-filter').stat().st_mode & 0o111 == 0o111
    for identifier, directory, script in [(ids[1], 'CommandLineOn', 'preinstall'), (ids[2], 'CommandLineOff', 'postinstall')]:
        path, _ = packages[identifier]
        expected = (ROOT/'MacApp/InstallerScripts'/directory/script).read_text()
        expected = expected.replace('/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools', packaging.CLI_ROOT)
        expected = expected.replace('org.mail-filter.command-line', packaging.PATH_ID)
        assert {p.name for p in (path/'Scripts').iterdir()} == {script}
        assert (path/'Scripts'/script).read_text() == expected
    for path in root.rglob('*'):
        assert path.name not in ('settings.json', 'accounts.txt', 'activity.json', 'junk-protection.json', 'model-failures.json'), path
print('Verified Dev-only app identity/destination, intact signatures, version/build display, optional isolated CLI and no private state.')
