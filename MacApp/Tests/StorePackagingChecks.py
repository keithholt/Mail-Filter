"""Exercise release payload rejection on disposable copies of an unsigned archive."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
verify = Path(__file__).resolve().parents[1] / 'Store/verify.py'
with tempfile.TemporaryDirectory(prefix='mail-filter-store-payload-') as temp:
    app = Path(temp) / 'Mail-Filter.app'
    shutil.copytree(source, app, symlinks=True)
    def run():
        return subprocess.run([sys.executable, str(verify), str(app), '--unsigned', '--development'], capture_output=True).returncode
    assert run() == 0
    tools = app / 'Contents/Resources/DeveloperTools'
    tools.mkdir()
    assert run() != 0, 'Store payload must reject engineering tools'
    tools.rmdir()
    extra = app / 'Contents/MacOS/EngineeringCLI'
    extra.write_bytes(b'synthetic executable')
    assert run() != 0, 'Store payload must reject extra executables'
    extra.unlink()
    info_file = app / 'Contents/Info.plist'
    original = info_file.read_bytes()
    info = plistlib.loads(original)
    info['MailFilterAppGroup'] = 'group.example.wrong'
    info_file.write_bytes(plistlib.dumps(info))
    assert run() != 0, 'Mismatched storage identity must fail'
    info_file.write_bytes(original)
    privacy_file = app / 'Contents/Resources/PrivacyInfo.xcprivacy'
    original_privacy = privacy_file.read_bytes()
    privacy = plistlib.loads(original_privacy)
    privacy['NSPrivacyTracking'] = True
    privacy_file.write_bytes(plistlib.dumps(privacy))
    assert run() != 0, 'Unexpected tracking manifest must fail'
    privacy_file.write_bytes(original_privacy)
    assert run() == 0
print('Passed Store payload rejection checks: developer tools, extra executable, wrong group and altered privacy manifest.')
