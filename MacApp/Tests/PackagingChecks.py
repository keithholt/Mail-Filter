"""Exercise privileged PATH scripts against temporary volumes, never /etc."""
from pathlib import Path
import subprocess
import tempfile

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
        result = subprocess.run(['/bin/sh',str(guard)],capture_output=True,text=True,timeout=5)
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
    result = subprocess.run(['/bin/sh',str(guard)],capture_output=True,text=True,timeout=5)
    assert result.returncode != 0 and 'could not check running applications' in result.stderr
print('Update guard checks passed: running hosts, stale extension, other users, idle machine and process-list failure; no apps stopped or payload installed')
