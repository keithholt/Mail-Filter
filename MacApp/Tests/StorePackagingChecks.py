"""Exercise release payload rejection on disposable copies of an unsigned archive."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
source_info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
identity_flags = ['--development'] if source_info['CFBundleIdentifier'] == 'org.mail-filter.development' else []
verify = Path(__file__).resolve().parents[1] / 'Store/verify.py'
with tempfile.TemporaryDirectory(prefix='mail-filter-store-payload-') as temp:
    app = Path(temp) / 'Mail-Filter.app'
    shutil.copytree(source, app, symlinks=True)
    def run():
        return subprocess.run([sys.executable, str(verify), str(app), '--unsigned', *identity_flags], capture_output=True).returncode
    assert run() == 0
    extension = app / 'Contents/PlugIns/Mail-Filter.appex'
    extension_info_file = extension / 'Contents/Info.plist'
    original_extension_info = extension_info_file.read_bytes()
    extension_info = plistlib.loads(original_extension_info)
    executable = extension / 'Contents/MacOS' / extension_info['CFBundleExecutable']
    mismatched_executable = executable.with_name('MismatchedExtension')
    executable.rename(mismatched_executable)
    extension_info['CFBundleExecutable'] = mismatched_executable.name
    extension_info_file.write_bytes(plistlib.dumps(extension_info))
    assert run() != 0, 'Existing executable with a different .appex basename must fail (App Store 90362)'
    mismatched_executable.rename(executable)
    extension_info_file.write_bytes(original_extension_info)
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
    info = plistlib.loads(original)
    info.pop('NSHumanReadableCopyright', None)
    info_file.write_bytes(plistlib.dumps(info))
    assert run() != 0, 'Missing app copyright must fail'
    info_file.write_bytes(original)
    privacy_file = app / 'Contents/Resources/PrivacyInfo.xcprivacy'
    original_privacy = privacy_file.read_bytes()
    privacy = plistlib.loads(original_privacy)
    privacy['NSPrivacyTracking'] = True
    privacy_file.write_bytes(plistlib.dumps(privacy))
    assert run() != 0, 'Unexpected tracking manifest must fail'
    privacy_file.write_bytes(original_privacy)
    assert run() == 0
print('Passed Store payload rejection checks: extension executable basename, developer tools, extra executable, wrong group, missing copyright and altered privacy manifest.')
