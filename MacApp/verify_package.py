"""Expand and inspect an installer; never install it or access real mail."""
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

scripts = Path(__file__).parent/'InstallerScripts'
with tempfile.TemporaryDirectory(prefix='mail-filter-package-check-') as directory:
    root = Path(directory)/'expanded'
    subprocess.run(['/usr/sbin/pkgutil','--expand-full',sys.argv[1],str(root)],check=True,stdout=subprocess.DEVNULL)
    distribution = ET.parse(root/'Distribution').getroot()
    assert distribution.find('title').text == 'Mail-Filter'
    assert distribution.find('options').attrib['customize'] == 'always'
    choices = {choice.attrib['id']: choice for choice in distribution.findall('choice')}
    assert set(choices) == {'app','commandLine','commandLineOff'}
    assert choices['app'].attrib['selected'] == 'true'
    assert choices['commandLine'].attrib['start_selected'] == 'true'
    assert 'selected' not in choices['commandLine'].attrib, 'Visible choice must remain user-controlled'
    assert choices['commandLineOff'].attrib['visible'] == 'false'
    assert choices['commandLineOff'].attrib['selected'] == '!choices.commandLine.selected'
    assert choices['commandLine'].find('pkg-ref').attrib['id'] == 'org.mail-filter.command-line.enabled'
    assert choices['commandLineOff'].find('pkg-ref').attrib['id'] == 'org.mail-filter.command-line.disabled'
    packages = {}
    for info in root.rglob('PackageInfo'):
        metadata = ET.parse(info).getroot()
        packages[metadata.attrib['identifier']] = (info.parent, metadata)
    assert set(packages) == {'org.mail-filter.installer','org.mail-filter.command-line.enabled','org.mail-filter.command-line.disabled'}
    app, info = packages['org.mail-filter.installer']
    assert info.attrib['install-location'] == '/Applications'
    payload = app/'Payload'
    assert {p.name for p in payload.iterdir()} == {'Mail-Filter.app','Uninstall Mail-Filter.app'}
    for path in payload.rglob('*'):
        assert path.name not in ('configuration.json','settings.json','accounts.txt','processed.json','junk-protection.json','activity.json'), path
    assert not (app/'Scripts').exists(), 'Main package must not run scripts'
    for path in payload.glob('*.app'):
        subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(path)],check=True)
    cli = payload/'Mail-Filter.app/Contents/Resources/DeveloperTools'
    subprocess.run(['/usr/bin/codesign','--verify','--strict',str(cli/'libexec/mail-filter')],check=True)
    assert (cli/'bin/mail-filter').stat().st_mode & 0o111 == 0o111
    on, info = packages['org.mail-filter.command-line.enabled']
    assert info.attrib['install-location'] == '/'
    files = {p.relative_to(on/'Payload').as_posix() for p in (on/'Payload').rglob('*') if not p.is_dir()}
    assert files == {'etc/paths.d/org.mail-filter.command-line'}
    path_entry = on/'Payload/etc/paths.d/org.mail-filter.command-line'
    assert path_entry.read_text() == '/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin\n'
    assert {p.name for p in (on/'Scripts').iterdir()} == {'preinstall'}
    assert (on/'Scripts/preinstall').read_bytes() == (scripts/'CommandLineOn/preinstall').read_bytes()
    off, info = packages['org.mail-filter.command-line.disabled']
    if (off/'Payload').is_dir(): assert not list((off/'Payload').rglob('*'))
    assert {p.name for p in (off/'Scripts').iterdir()} == {'postinstall'}
    assert (off/'Scripts/postinstall').read_bytes() == (scripts/'CommandLineOff/postinstall').read_bytes()
print('Verified app and CLI signatures, installer choices, bounded PATH components and absence of personal data')
