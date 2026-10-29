"""Exercise privileged PATH scripts against temporary volumes, never /etc."""
from pathlib import Path
import subprocess
import tempfile
import plistlib
import importlib.util

scripts = Path(__file__).resolve().parents[1]/'InstallerScripts'
entry = b'/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin\n'


def run_script(script, volume):
    return subprocess.run(['/bin/sh', str(script), 'unused.pkg', '/', str(volume)],
                          capture_output=True, timeout=5).returncode


with tempfile.TemporaryDirectory(prefix='mail-filter-path-check-') as directory:
    volume = Path(directory)
    paths = volume/'etc/paths.d'
    paths.mkdir(parents=True)
    owned = paths/'org.mail-filter.command-line'
    other = paths/'unrelated-tool'
    other.write_bytes(b'/another/tool/bin\n')
    on = scripts/'CommandLineOn/preinstall'
    off = scripts/'CommandLineOff/postinstall'
    assert run_script(on, volume) == 0 and not owned.exists()
    assert run_script(off, volume) == 0
    owned.write_bytes(entry)
    assert run_script(on, volume) == 0 and owned.read_bytes() == entry
    assert run_script(off, volume) == 0 and not owned.exists()
    for content in (b'/unrelated/tool\n', entry+b'/another/path\n'):
        owned.write_bytes(content)
        assert run_script(on, volume) != 0
        assert run_script(off, volume) != 0 and owned.read_bytes() == content
        owned.unlink()
    target = volume/'protected-file'
    target.write_bytes(entry)
    for destination in (target, volume/'missing-file'):
        owned.symlink_to(destination)
        assert run_script(on, volume) != 0
        assert run_script(off, volume) != 0 and owned.is_symlink()
        assert target.read_bytes() == entry
        owned.unlink()
    owned.mkdir()
    assert run_script(on, volume) != 0
    assert run_script(off, volume) != 0 and owned.is_dir()
    assert other.read_bytes() == b'/another/tool/bin\n'
print('PATH script checks passed: enable/disable, repeated runs, unrelated content, symlinks, missing targets and directories; real /etc untouched')

# Run the real update guard with only its process-list command substituted in a
# temporary copy. No real apps are stopped and no package payload is installed.
with tempfile.TemporaryDirectory(prefix='mail-filter-update-check-') as directory:
    root = Path(directory)
    process_list = root/'processes'
    guard = root/'preinstall'
    source = (scripts/'App/preinstall').read_text()
    assert source.count('/bin/ps -axo comm=') == 1
    guard.write_text(source.replace('/bin/ps -axo comm=', '/bin/cat ' + str(process_list)))
    def check_processes(processes, blocked):
        process_list.write_text('\n'.join(processes) + '\n')
        result = subprocess.run(['/bin/sh',str(guard),'unused.pkg','/',str(root)],capture_output=True,text=True,timeout=5)
        assert (result.returncode != 0) == blocked, processes
        if blocked: assert 'No app files have been replaced' in result.stderr
    check_processes([], False)
    check_processes(['/usr/bin/Terminal','/System/Library/OtherMailHelper'], False)
    for process in (
        '/System/Applications/Mail.app/Contents/MacOS/Mail',
        '/Applications/Mail-Filter.app/Contents/MacOS/MailFilter',
        '/Applications/Mail-Filter.app/Contents/PlugIns/Mail-Filter.appex/Contents/MacOS/MailFilterExtension',
        '/Applications/Mail-Filter.app/Contents/PlugIns/Mail-Filter.appex/Contents/MacOS/Mail-Filter',
        '/Applications/Uninstall Mail-Filter.app/Contents/MacOS/MailFilterUninstaller',
        '/Users/another-user/Applications/Mail-Filter.app/Contents/MacOS/MailFilter',
    ):
        check_processes([process], True)
    guard.write_text(source.replace('/bin/ps -axo comm=', '/usr/bin/false'))
    result = subprocess.run(['/bin/sh',str(guard),'unused.pkg','/',str(root)],capture_output=True,text=True,timeout=5)
    assert result.returncode != 0 and 'could not check running applications' in result.stderr
print('Update guard checks passed: running hosts, stale extension, other users, idle machine and process-list failure; no apps stopped or payload installed')

# Execute both real guards on synthetic target volumes. No production paths are
# redirected by installer environment variables; only ps is stubbed in test copies.
with tempfile.TemporaryDirectory(prefix='mail-filter-identity-check-') as directory:
    volume = Path(directory)
    apps = volume/'Applications'
    apps.mkdir()
    def guard_result(channel):
        script = volume/'preinstall'
        script.write_text((scripts/channel/'preinstall').read_text().replace('/bin/ps -axo comm=', '/usr/bin/true'))
        return subprocess.run(['/bin/sh',str(script),'unused.pkg','/',str(volume)],capture_output=True,text=True,timeout=5)
    def product(name, identifier, distribution='direct', receipt=False):
        app = apps/name
        (app/'Contents').mkdir(parents=True)
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'MailFilterDistribution':distribution}))
        if receipt:
            (app/'Contents/_MASReceipt').mkdir()
            (app/'Contents/_MASReceipt/receipt').write_bytes(b'test receipt')
        return app
    import shutil
    for identifier, distribution, receipt, blocked in [
        ('org.mail-filter.app','direct',False,False),
        ('org.mail-filter.app','app-store',False,True),
        ('org.mail-filter.app','app-store',True,True),
        ('org.mail-filter.app','direct',True,True),
        ('another.app','direct',False,True),
        ('org.mail-filter.app','',False,True),
    ]:
        app = product('Mail-Filter.app', identifier, distribution, receipt)
        before = (app/'Contents/Info.plist').read_bytes()
        assert (guard_result('App').returncode != 0) == blocked
        assert (app/'Contents/Info.plist').read_bytes() == before
        # Dev installs are independent of every possible production copy.
        assert guard_result('Development').returncode == 0
        shutil.rmtree(app)
    for identifier, receipt, blocked in [
        ('org.mail-filter.development',False,False),('org.mail-filter.app',False,True),
        ('org.mail-filter.development',True,True),
    ]:
        app = product('Mail-Filter Dev.app', identifier, 'app-store', receipt)
        assert (guard_result('Development').returncode != 0) == blocked
        shutil.rmtree(app)
    for channel, name in [('App','Mail-Filter.app'),('Development','Mail-Filter Dev.app')]:
        app = apps/name
        app.symlink_to(volume/'nonexistent.app')
        assert guard_result(channel).returncode != 0 and app.is_symlink()
        app.unlink()
    # New Dev guard blocks both old personal and new system Dev processes.
    script = volume/'preinstall'
    process_list = volume/'processes'
    script.write_text((scripts/'Development/preinstall').read_text().replace('/bin/ps -axo comm=', '/bin/cat '+str(process_list)))
    for process in ['/System/Applications/Mail.app/Contents/MacOS/Mail',
                    '/Applications/Mail-Filter Dev.app/Contents/MacOS/MailFilter',
                    '/Users/example/Applications/Mail-Filter Dev.app/Contents/PlugIns/Mail-Filter.appex/Contents/MacOS/Mail-Filter']:
        process_list.write_text(process+'\n')
        assert subprocess.run(['/bin/sh',str(script),'unused.pkg','/',str(volume)],capture_output=True).returncode != 0
print('Installer identity checks passed: Store receipt/metadata protection, Dev independence, wrong identities, symlinks and in-use Dev copies; all checks used temporary volumes.')

spec = importlib.util.spec_from_file_location('dev_packaging', scripts.parent/'package-dev.py')
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)
with tempfile.TemporaryDirectory(prefix='mail-filter-shortcut-check-') as directory:
    root = Path(directory)
    desktop = root/'Desktop'
    desktop.mkdir()
    (root/'outputs').mkdir()
    old = root/'outputs/Mail-Filter Installer.pkg'
    link = desktop/old.name
    for kind in ('owned', 'unrelated-file', 'unrelated-link'):
        old.write_bytes(b'old installer to preserve')
        if kind == 'owned': link.symlink_to(old)
        elif kind == 'unrelated-file': link.write_bytes(b'user file')
        else: link.symlink_to(root/'unrelated.pkg')
        packaging.retire_legacy_installer(root, desktop)
        assert not old.exists()
        assert any(path.read_bytes() == b'old installer to preserve' for path in (root/'outputs/legacy-installers').iterdir())
        if kind == 'owned': assert not link.is_symlink()
        elif kind == 'unrelated-file': assert link.read_bytes() == b'user file'
        else: assert link.is_symlink() and link.readlink() == root/'unrelated.pkg'
        if link.exists() or link.is_symlink(): link.unlink()
print('Legacy installer shortcut checks passed: archived package bytes and preserved unrelated Desktop files/links.')

with tempfile.TemporaryDirectory(prefix='mail-filter-dev-path-check-') as directory:
    volume = Path(directory)
    paths = volume/'etc/paths.d'
    paths.mkdir(parents=True)
    legacy = paths/'org.mail-filter.command-line'
    legacy.write_bytes(entry)
    owned = paths/packaging.PATH_ID
    for name, filename in [('CommandLineOn','preinstall'),('CommandLineOff','postinstall')]:
        source = (scripts/name/filename).read_text()
        source = source.replace('/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools', packaging.CLI_ROOT)
        source = source.replace('org.mail-filter.command-line', packaging.PATH_ID)
        (volume/name).write_text(source)
    on, off = volume/'CommandLineOn', volume/'CommandLineOff'
    assert run_script(on, volume) == 0
    owned.write_text(packaging.CLI_ROOT+'/bin\n')
    assert run_script(on, volume) == 0
    assert run_script(off, volume) == 0 and not owned.exists()
    owned.write_bytes(b'/another/tool\n')
    assert run_script(on, volume) != 0 and run_script(off, volume) != 0
    assert owned.read_bytes() == b'/another/tool\n'
    assert legacy.read_bytes() == entry
print('Dev PATH checks passed: independent owned filename, enable/disable and unrelated legacy entry preserved.')
