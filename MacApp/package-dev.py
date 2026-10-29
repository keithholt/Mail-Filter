#!/usr/bin/env python3
"""Package signed Development products, preserving the host's original seal.

The Dev host and extension remain distinct from Store. Engineering CLI resources
are a separate, optional payload outside both app bundles and both App Groups.
"""
from pathlib import Path
import html
import datetime
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CLI_ROOT = '/Library/Application Support/Mail-Filter Dev/DeveloperTools'
PATH_ID = 'org.mail-filter.development.command-line'


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def retire_legacy_installer(root=ROOT, desktop=None):
    desktop = desktop if desktop is not None else Path.home()/'Desktop'
    old = desktop/'Mail-Filter Installer.pkg'
    old_package = root/'outputs/Mail-Filter Installer.pkg'
    try:
        if old.is_symlink() and old.resolve() == old_package.resolve():
            old.unlink()
        if old_package.is_file():
            archive = root/'outputs/legacy-installers'
            archive.mkdir(exist_ok=True)
            old_package.rename(archive/(datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f-')+old_package.name))
    except OSError as error:
        print(f'Warning: Could not retire the old generic installer: {error}. Use only Mail-Filter Dev Installer.pkg.', file=sys.stderr)


def package(products):
    source = products / 'Mail-Filter.app'
    run(sys.executable, ROOT/'MacApp/Store/verify.py', source, '--development')
    info = plistlib.loads((source/'Contents/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', version) or not re.fullmatch(r'\d+', build):
        raise ValueError('Expected numeric version and build')
    if info['CFBundleDisplayName'] != 'Mail-Filter Dev':
        raise ValueError('Refusing to package another distribution')
    run('/usr/bin/codesign', '--verify', '--strict', products/'mail-filter')
    label = f'Mail-Filter Dev {version} (build {build})'
    work = ROOT/'.build/dev-package'
    if work.exists():
        shutil.rmtree(work)
    (work/'Payload').mkdir(parents=True)
    resources = work/'Resources'
    resources.mkdir()
    run('/usr/bin/ditto', source, work/'Payload/Mail-Filter Dev.app')
    # Copying a bundle under its display name does not change its code signature.
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', work/'Payload/Mail-Filter Dev.app')
    tools = work/'CommandLinePayload'/CLI_ROOT.lstrip('/')
    for name in ('bin', 'libexec', 'prompts', 'config'):
        (tools/name).mkdir(parents=True)
    shutil.copy2(products/'mail-filter', tools/'libexec/mail-filter')
    for name in ('filter.txt', 'political-evidence.txt'):
        shutil.copy2(ROOT/'prompts'/name, tools/'prompts'/name)
    shutil.copy2(ROOT/'config/accounts.example.txt', tools/'config/accounts.example.txt')
    shutil.copy2(ROOT/'README-DEVELOPER.md', tools/'README-DEVELOPER.md')
    launcher = tools/'bin/mail-filter'
    launcher.write_text('#!/bin/zsh\nset -eu\nexport MAIL_FILTER_ROOT="${0:A:h:h}"\nexec "$MAIL_FILTER_ROOT/libexec/mail-filter" "$@"\n')
    launcher.chmod(0o755)
    paths = work/'CommandLinePayload/etc/paths.d'
    paths.mkdir(parents=True)
    (paths/PATH_ID).write_text(CLI_ROOT+'/bin\n')
    # Reuse the bounded PATH guards, with a different owned filename and entry.
    for name, script in [('CommandLineOn', 'preinstall'), ('CommandLineOff', 'postinstall')]:
        destination = work/name
        destination.mkdir()
        text = (ROOT/'MacApp/InstallerScripts'/name/script).read_text()
        text = text.replace('/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools', CLI_ROOT)
        text = text.replace('org.mail-filter.command-line', PATH_ID)
        (destination/script).write_text(text)
        (destination/script).chmod(0o755)
    run('/usr/bin/pkgbuild', '--analyze', '--root', work/'Payload', work/'components.plist')
    components = plistlib.loads((work/'components.plist').read_bytes())
    for component in components:
        component.update(BundleIsRelocatable=False, BundleHasStrictIdentifier=True,
                         BundleIsVersionChecked=True, BundleOverwriteAction='upgrade')
    (work/'components.plist').write_bytes(plistlib.dumps(components))
    ids = ['org.mail-filter.development.installer', PATH_ID+'.enabled', PATH_ID+'.disabled']
    package_version = version+'.'+build
    run('/usr/bin/pkgbuild', '--root', work/'Payload', '--component-plist', work/'components.plist',
        '--scripts', ROOT/'MacApp/InstallerScripts/Development', '--identifier', ids[0],
        '--version', package_version, '--install-location', '/Applications', work/'App.pkg')
    run('/usr/bin/pkgbuild', '--root', work/'CommandLinePayload', '--ownership', 'recommended',
        '--scripts', work/'CommandLineOn', '--identifier', ids[1], '--version', package_version,
        '--install-location', '/', work/'CommandLine.pkg')
    run('/usr/bin/pkgbuild', '--nopayload', '--scripts', work/'CommandLineOff', '--identifier', ids[2],
        '--version', package_version, work/'CommandLineOff.pkg')
    # Let Apple's product builder generate OS/architecture eligibility checks.
    (work/'requirements.plist').write_bytes(plistlib.dumps({'os':['26.0'], 'arch':['arm64']}))
    run('/usr/bin/productbuild', '--synthesize', '--product', work/'requirements.plist',
        '--package', work/'App.pkg', '--package', work/'CommandLine.pkg',
        '--package', work/'CommandLineOff.pkg', work/'Base.xml')
    dist = ET.parse(work/'Base.xml').getroot()
    for element in list(dist):
        if element.tag in ('choices-outline', 'choice', 'pkg-ref', 'options'):
            dist.remove(element)
    ET.SubElement(dist, 'title').text = label
    ET.SubElement(dist, 'options', {'customize':'always', 'require-scripts':'true', 'hostArchitectures':'arm64'})
    ET.SubElement(dist, 'domains', {'enable_localSystem':'true', 'enable_currentUserHome':'false', 'enable_anywhere':'false'})
    ET.SubElement(dist, 'welcome', {'file':'Welcome.html', 'mime-type':'text/html'})
    ET.SubElement(dist, 'conclusion', {'file':'Finished.html', 'mime-type':'text/html'})
    outline = ET.SubElement(dist, 'choices-outline')
    for name in ('app', 'commandLine', 'commandLineOff'):
        ET.SubElement(outline, 'line', {'choice':name})
    choice = ET.SubElement(dist, 'choice', {'id':'app', 'title':label, 'visible':'false', 'selected':'true', 'enabled':'false'})
    ET.SubElement(choice, 'pkg-ref', {'id':ids[0]})
    choice = ET.SubElement(dist, 'choice', {'id':'commandLine', 'title':'Add engineering command-line tool to PATH',
        'description':'Install the independent development CLI. Uncheck to remove only the Dev installer PATH entry. App settings remain separate.', 'start_selected':'true'})
    ET.SubElement(choice, 'pkg-ref', {'id':ids[1]})
    choice = ET.SubElement(dist, 'choice', {'id':'commandLineOff', 'visible':'false',
        'selected':'!choices.commandLine.selected', 'enabled':'false'})
    ET.SubElement(choice, 'pkg-ref', {'id':ids[2]})
    for identifier, filename in zip(ids, ('App.pkg', 'CommandLine.pkg', 'CommandLineOff.pkg')):
        ET.SubElement(dist, 'pkg-ref', {'id':identifier, 'version':package_version}).text = filename
    close = ET.SubElement(ET.SubElement(dist, 'pkg-ref', {'id':ids[0]}), 'must-close')
    for identifier in ('com.apple.mail', 'org.mail-filter.development'):
        ET.SubElement(close, 'app', {'id':identifier})
    ET.ElementTree(dist).write(work/'Distribution.xml', encoding='utf-8', xml_declaration=True)
    header = '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:-apple-system;font-size:14px">'
    (resources/'Welcome.html').write_text(header+f'<h2>{html.escape(label)}</h2>'
        '<p>Installs <b>Mail-Filter Dev.app</b> in <b>/Applications</b>, beside the separately installed App Store <b>Mail-Filter.app</b>.</p>'
        '<p>Requires macOS 26 or later, Apple silicon, and Apple Intelligence. This development-signed app is for Macs registered in its provisioning profile; it is not a public notarized release.</p>'
        '<p>Quit Mail and Mail-Filter Dev before updating. Existing Dev settings, activity and restored-message protection are preserved. Store settings and the Store app are not changed.</p>'
        '<p>Enable exactly one Mail-Filter extension in Mail Settings. Mail presents independent checkboxes and cannot enforce this choice for us.</p>'
        '<p>If an older Dev copy is in your personal Applications folder, move that copy out of Applications before installing; keep its private settings.</p></body></html>')
    (resources/'Finished.html').write_text(header+f'<h2>{html.escape(label)} installed</h2>'
        '<p>Open <b>Mail-Filter Dev</b> from Applications. Confirm version and build in its sidebar. Reopen Mail, disable <b>Mail-Filter</b>, then enable <b>Mail-Filter Dev</b> when testing. Reverse those choices for Store filtering.</p>'
        '<p>The settings, accounts and protection records are separate. Installation does not enable either extension or move mail.</p>'
        '<p>If the optional CLI was selected, open a new Terminal window. It uses independent CLI settings and should not run alongside live extension filtering.</p></body></html>')
    out = ROOT/'outputs/Mail-Filter Dev Installer.pkg'
    out.parent.mkdir(exist_ok=True)
    run('/usr/bin/productbuild', '--distribution', work/'Distribution.xml', '--resources', resources,
        '--package-path', work, out)
    run(sys.executable, ROOT/'MacApp/verify_dev_package.py', out)
    # Retire only our old generic shortcut/package. Preserve arbitrary Desktop files.
    retire_legacy_installer()
    run(sys.executable, ROOT/'MacApp/desktop_shortcut.py', out)
    print(f'Installer ready: {out}\n{label}; Store app and private data unchanged.')


if __name__ == '__main__':
    package(Path(sys.argv[1]).resolve())
