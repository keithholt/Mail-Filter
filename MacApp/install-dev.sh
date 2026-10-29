#!/bin/zsh
# Stages only the signed, isolated Development configuration. Never replaces
# /Applications/Mail-Filter.app or imports its data or activates Mail extensions.
set -eu
root=${0:A:h:h}
[[ $# == 0 || ($# == 1 && "$1" == --no-build) ]] || {
    print -u2 'Usage: MacApp/install-dev.sh [--no-build]'; exit 1
}
if [[ $# == 0 ]]; then "$root/MacApp/store-build.sh" development; fi
source_app="${MAIL_FILTER_DERIVED_DATA_PATH:-$root/.build/xcode-derived}/Build/Products/Development/Mail-Filter.app"
python3 "$root/MacApp/Store/verify.py" "$source_app" --development
python3 - "$root" "$source_app" <<'PY'
from pathlib import Path
import datetime, os, plistlib, subprocess, sys, tempfile
root, source = map(Path, sys.argv[1:])
destination = Path('/Applications/Mail-Filter Dev.app')
personal = Path.home() / 'Applications/Mail-Filter Dev.app'
launch_services = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
def info(path):
    return plistlib.loads((path / 'Contents/Info.plist').read_bytes())
def unregister(path):
    result = subprocess.run(['/usr/bin/pluginkit', '-r', str(path)], capture_output=True, text=True)
    # An already-absent registration is normal after a prior staging run.
    # In-use/registry failures still stop the update rather than being ignored.
    if result.returncode and not (result.returncode == 1 and
            ('remove: no plugin at ' + str(path)) in (result.stdout + result.stderr)):
        raise RuntimeError('Could not unregister Dev extension: ' + result.stdout + result.stderr)
def unregister_host(path):
    result = subprocess.run([launch_services, '-u', str(path)], capture_output=True, text=True)
    # kLSApplicationNotFoundErr is expected when a built app was never launched
    # or a preceding staging run already removed its registration.
    if result.returncode and '-10814' not in (result.stdout + result.stderr):
        raise RuntimeError('Could not unregister Dev host: ' + result.stdout + result.stderr)
metadata = info(source)
if (metadata.get('CFBundleIdentifier'), metadata.get('CFBundleDisplayName'), metadata.get('MailFilterAppGroup')) != (
    'org.mail-filter.development', 'Mail-Filter Dev', 'group.org.mail-filter.development.shared'):
    raise ValueError('Refusing to stage a non-Dev product')
processes = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
if '/Mail.app/Contents/MacOS/Mail' in processes or any(
        path + '/Contents/' in processes for path in (str(destination), str(personal), str(source))):
    raise ValueError('Quit Mail and Mail-Filter Dev before replacing this development app')
for installed in (destination, personal):
    if not installed.exists() and not installed.is_symlink():
        continue
    if installed.is_symlink() or info(installed).get('CFBundleIdentifier') != 'org.mail-filter.development':
        raise ValueError('Refusing to replace another app')
    if installed == destination and installed.stat().st_uid != os.geteuid():
        raise ValueError('Use Mail-Filter Dev Installer.pkg to update this administrator-owned app; nothing was unregistered or replaced')
destination.parent.mkdir(parents=True, exist_ok=True)
unregister(source / 'Contents/PlugIns/Mail-Filter.appex')
unregister_host(source)
with tempfile.TemporaryDirectory(prefix='.mail-filter-dev-', dir=destination.parent) as temp:
    staged = Path(temp) / destination.name
    subprocess.run(['/usr/bin/ditto', str(source), str(staged)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
    for installed in (destination, personal):
        if not installed.exists():
            continue
        backup = root / 'outputs/development' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup.mkdir(parents=True)
        unregister(installed / 'Contents/PlugIns/Mail-Filter.appex')
        unregister_host(installed)
        os.rename(installed, backup / installed.name)
    os.rename(staged, destination)
subprocess.run([launch_services, '-f', str(destination)], check=True)
subprocess.run(['/usr/bin/pluginkit', '-a', str(destination / 'Contents/PlugIns/Mail-Filter.appex')], check=True)
print('Installed ' + str(destination))
print('Separate development settings and extension; no setup was imported and no extension was enabled.')
PY
