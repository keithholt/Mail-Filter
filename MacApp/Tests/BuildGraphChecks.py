"""Check native build graph boundaries without compiling or running a product."""
from pathlib import Path
import copy
import json
import importlib.util
import plistlib
import subprocess
import runpy
import sys
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
project = root / 'Mail-Filter.xcodeproj'
payload = json.loads(subprocess.check_output(
    ['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(project / 'project.pbxproj')]))
objects = payload['objects']
compiled_refs = {value['fileRef'] for value in objects.values() if value['isa'] == 'PBXBuildFile'}
for key, value in objects.items():
    if value['isa'] == 'PBXFileReference' and (value.get('path', '').startswith(('MacApp/ModelCheck/', 'MacApp/Tests/'))
            or value.get('path') in ('MacApp/ModelProbe.swift', 'MacApp/LocalModelReplay.swift')):
        assert key not in compiled_refs, 'Standalone model investigation code leaked into a shipping target'
targets = {value['name']: key for key, value in objects.items() if value['isa'] in ('PBXNativeTarget', 'PBXAggregateTarget')}
environment_ref = next(key for key, value in objects.items() if value.get('path') == 'MacApp/Shared/ModelEnvironment.swift')
for name, key in targets.items():
    members = {objects[item].get('fileRef') for phase in objects[key].get('buildPhases', [])
               for item in objects[phase].get('files', [])}
    assert (environment_ref in members) == (name == 'MailFilter'), 'Read-only environment collector must belong only to the settings app'


def closure(ids):
    result = set(ids)
    todo = list(ids)
    while todo:
        for dependency in objects[todo.pop()].get('dependencies', []):
            target = objects[dependency]['target']
            if target not in result:
                result.add(target)
                todo.append(target)
    return result


def scheme(name):
    return ET.parse(project / 'xcshareddata/xcschemes' / (name + '.xcscheme')).getroot()


def build_ids(xml):
    return [item.attrib['BlueprintIdentifier'] for item in xml.findall('./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference')]


store = scheme('Mail-Filter Store')
store_graph = closure(build_ids(store))
assert store_graph == {targets[name] for name in ('MailFilter', 'MailFilterExtension', 'MailFilterDocumentation')}
assert store.find('LaunchAction').attrib['buildConfiguration'] == 'Development'
assert store.find('ArchiveAction').attrib['buildConfiguration'] == 'Store'
development = (root / 'MacApp/Build/Development.xcconfig').read_text()
production = (root / 'MacApp/Build/Store.xcconfig').read_text()
assert 'MAIL_FILTER_DISPLAY_NAME = Mail-Filter Dev\n' in development
assert 'MAIL_FILTER_BUNDLE_ID = org.mail-filter.development\n' in development
assert 'MAIL_FILTER_APP_GROUP = group.org.mail-filter.development.shared\n' in development
assert 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) APP_STORE MAIL_FILTER_DEV\n' in development
for config in (root / 'MacApp/Build').glob('*.xcconfig'):
    if config.name not in ('Development.xcconfig', 'Signing.local.xcconfig'):
        assert 'MAIL_FILTER_DEV' not in config.read_text(), f'Dev self-mail bypass leaked into {config.name}'
assert 'MAIL_FILTER_BUNDLE_ID = org.mail-filter.app\n' in production
assert 'MAIL_FILTER_APP_GROUP = group.org.mail-filter.shared\n' in production
installer_graph = closure(build_ids(scheme('Mail-Filter Local Installer')))
assert installer_graph == set(targets.values()), 'Installer must build every direct product before packaging'
assert closure(build_ids(scheme('Mail-Filter Local'))) == installer_graph - {targets['MailFilterLocalInstaller']}
assert scheme('Mail-Filter Build Check').find('./LaunchAction/BuildableProductRunnable') is None
assert scheme('mail-filter CLI').find('./LaunchAction/CommandLineArguments/CommandLineArgument').attrib['argument'] == '--help'
for value in objects.values():
    if value['isa'] == 'PBXFileReference' and value.get('sourceTree') == 'SOURCE_ROOT':
        assert (root / value['path']).exists(), value['path']
        assert not value['path'].startswith('../'), value['path']
        assert not any(name in value['path'] for name in ('Signing.local.xcconfig', 'xcuserdata/', '.build/', 'outputs/'))
for name in ('MailFilter', 'MailFilterExtension', 'MailFilterCLI', 'MailFilterUninstaller'):
    configurations = objects[objects[targets[name]]['buildConfigurationList']]['buildConfigurations']
    assert {objects[key]['name'] for key in configurations} == {'Local', 'DeveloperID', 'BuildCheck', 'Development', 'Store'}
    assert targets['MailFilterDocumentation'] in closure([targets[name]])
extension_configurations = objects[objects[targets['MailFilterExtension']]['buildConfigurationList']]['buildConfigurations']
for key in extension_configurations:
    configuration = objects[key]
    settings = configuration['buildSettings']
    expected_executable = 'MailFilterExtension' if configuration['name'] in ('Local', 'DeveloperID') else '$(PRODUCT_NAME)'
    assert settings['EXECUTABLE_NAME'] == expected_executable, configuration['name']
    assert settings['PRODUCT_MODULE_NAME'] == 'MailFilterExtension'
for role in ('Host', 'Extension', 'Uninstaller'):
    info = plistlib.loads((root / 'MacApp/Build' / (role + '-Local-Info.plist')).read_bytes())
    assert 'MailFilterAppGroup' not in info, 'Local storage must not acquire a group dependency'
for filename in ('Extension-Info.plist', 'Extension-Local-Info.plist'):
    info = plistlib.loads((root/'MacApp/Build'/filename).read_bytes())
    assert info['CFBundleDisplayName'] == '$(MAIL_FILTER_DISPLAY_NAME) (build $(CURRENT_PROJECT_VERSION))'
    assert info['CFBundleShortVersionString'] == '$(MARKETING_VERSION)', 'Keep Store version syntax numeric'
local_extension = plistlib.loads((root / 'MacApp/Build/Extension-Local.entitlements').read_bytes())
assert local_extension['com.apple.security.temporary-exception.files.home-relative-path.read-write'] == ['/Library/Application Support/Mail-Filter Local/']
# Xcode rewrites project syntax and upgrade metadata during ordinary editing.
# Those edits must pass --check, while a changed configuration must still fail.
previous_arguments = sys.argv
try:
    sys.argv = [str(root / 'MacApp/generate-project.py'), '--check']
    generated = runpy.run_path(sys.argv[0])
finally:
    sys.argv = previous_arguments
project_text = (project / 'project.pbxproj').read_text()
reformatted = copy.deepcopy(payload)
reformatted['objects'][reformatted['rootObject']]['attributes']['LastUpgradeCheck'] = '9999'
reformatted['objects'][reformatted['rootObject']]['hasScannedForEncodings'] = '1'
assert generated['project_matches'](project_text, plistlib.dumps(reformatted).decode())
local_config = next(key for key in objects[objects[targets['MailFilter']]['buildConfigurationList']]['buildConfigurations']
                    if objects[key]['name'] == 'Local')
reformatted['objects'][local_config]['buildSettings']['CODE_SIGNING_ALLOWED'] = 'NO'
assert not generated['project_matches'](project_text, plistlib.dumps(reformatted).decode())
check_scheme = project / 'xcshareddata/xcschemes/Mail-Filter Build Check.xcscheme'
reformatted_scheme = ET.fromstring(check_scheme.read_text())
reformatted_scheme.attrib['LastUpgradeVersion'] = '9999'
assert generated['scheme_matches'](check_scheme.read_text(), ET.tostring(reformatted_scheme, encoding='unicode'))
reformatted_scheme.find('LaunchAction').attrib['buildConfiguration'] = 'Store'
assert not generated['scheme_matches'](check_scheme.read_text(), ET.tostring(reformatted_scheme, encoding='unicode'))
spec = importlib.util.spec_from_file_location('direct_staging', root / 'MacApp/prepare-direct-products.py')
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)
with tempfile.TemporaryDirectory(prefix='mail-filter-distribution-boundary-') as temp:
    products = Path(temp) / 'products'
    output = Path(temp) / 'stage'
    output.mkdir()
    sentinel = output / 'keep'
    sentinel.write_text('existing staged product')
    info_file = products / 'Mail-Filter.app/Contents/Info.plist'
    info_file.parent.mkdir(parents=True)
    for distribution, storage in [('app-store', 'app-group'), ('direct', 'app-group')]:
        info_file.write_bytes(plistlib.dumps({'MailFilterDistribution': distribution, 'MailFilterStorageMode': storage}))
        try:
            staging.prepare(products, output, 'local', '-')
        except ValueError:
            pass
        else:
            raise AssertionError('Wrong distribution or storage accepted for a local package')
        assert sentinel.read_text() == 'existing staged product'
print('Passed native build graph boundaries: shared targets, Store exclusions, direct dependencies, local storage, CLI safety and repository references.')
