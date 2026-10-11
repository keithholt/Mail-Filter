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
