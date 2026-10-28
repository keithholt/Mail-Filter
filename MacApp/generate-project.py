#!/usr/bin/env python3
"""Generate the root Xcode project and shared schemes using Python's stdlib.

This is the native product source-list authority for every distribution channel.
The shell build entry points invoke these targets rather than compiling Swift.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / 'Mail-Filter.xcodeproj'
CONFIGURATIONS = ('Local', 'DeveloperID', 'BuildCheck', 'Development', 'Store')
objects = {}


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(key_name, isa, **values):
    key = uid(key_name)
    objects[key] = dict(isa=isa, **values)
    return key


def ref(path, kind):
    return add('file:' + path, 'PBXFileReference', lastKnownFileType=kind,
               name=Path(path).name, path=path, sourceTree='SOURCE_ROOT')


def phase(name, isa, files, **extra):
    built = [add(name + ':' + f, 'PBXBuildFile', fileRef=f) for f in files]
    return add(name, isa, buildActionMask=2147483647, files=built,
               runOnlyForDeploymentPostprocessing=0, **extra)


shared = [
    'Sources/MailFilter/Core.swift', 'Sources/MailFilter/ClassificationRequest.swift',
    'Sources/MailFilter/PoliticalModel.swift', 'MacApp/SharedStore.swift',
    'MacApp/Shared/MIMEBodyDecoder.swift', 'MacApp/Shared/FilteringConfiguration.swift',
    'MacApp/Shared/JunkProtection.swift', 'MacApp/Shared/AnalysisDeadline.swift',
    'MacApp/Shared/ClassificationRetry.swift',
]
host = shared + ['Sources/MailFilter/MailAutomation.swift'] + [
    'MacApp/' + name + '.swift' for name in ('MailFilterApp', 'SettingsModel', 'SettingsView',
    'AccountInventory', 'MessageDiagnostics', 'SelectedEmailReport', 'DiagnosticReport', 'UninstallPlan')]
extension = shared + ['MacApp/' + name + '.swift' for name in (
    'NativeClassifier', 'NativeExtension', 'Shared/InspectionScheduler', 'Shared/BodyRequestTracker')]
uninstaller = shared + ['Sources/MailFilter/MailAutomation.swift',
                        'MacApp/UninstallPlan.swift', 'MacApp/UninstallerApp.swift']
cli = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'Sources/MailFilter').glob('*.swift'))
sources = {path: ref(path, 'sourcecode.swift') for path in sorted(set(host + extension + uninstaller + cli))}
assets = ref('MacApp/Build/Assets.xcassets', 'folder.assetcatalog')
privacy = ref('MacApp/Build/PrivacyInfo.xcprivacy', 'text.xml')
resources = [ref('MacApp/Resources/' + name, 'text') for name in ('filter.txt', 'political-evidence.txt')]
extension_frameworks = [add('framework:' + name, 'PBXFileReference', lastKnownFileType='wrapper.framework',
    name=name + '.framework', path='System/Library/Frameworks/' + name + '.framework', sourceTree='SDKROOT')
    for name in ('MailKit', 'AppKit')]
project_id = uid('project')
target_ids = {name: uid(name + '-target') for name in ('host', 'extension', 'uninstaller', 'cli', 'documentation', 'local-installer')}
products = {}
for name, path, kind in (
    ('host', 'Mail-Filter.app', 'wrapper.application'),
    ('extension', 'Mail-Filter.appex', 'wrapper.app-extension'),
    ('uninstaller', 'Uninstall Mail-Filter.app', 'wrapper.application'),
    ('cli', 'mail-filter', 'compiled.mach-o.executable'),
):
    products[name] = add(name + '-product', 'PBXFileReference', explicitFileType=kind,
                         path=path, sourceTree='BUILT_PRODUCTS_DIR')


def dependency(name):
    proxy = add(name + '-proxy', 'PBXContainerItemProxy', containerPortal=project_id,
                proxyType=1, remoteGlobalIDString=target_ids[name])
    return add(name + '-dependency', 'PBXTargetDependency', target=target_ids[name], targetProxy=proxy)


def configs(name, role=None):
    values = []
    for mode in CONFIGURATIONS:
        settings = {}
        if role in ('Host', 'Extension', 'Uninstaller'):
            local = mode == 'Local'
            direct = mode in ('Local', 'DeveloperID')
            template = role + ('-Local' if local else '')
            entitlement = role + ('-Local' if local else '-Direct' if direct else '')
            if role == 'Uninstaller' and not direct:
                # This target is excluded from Store schemes and dependencies.
                entitlement = 'Uninstaller-Local'
            settings.update(
                PRODUCT_NAME='Uninstall Mail-Filter' if role == 'Uninstaller' else 'Mail-Filter',
                EXECUTABLE_NAME={'Host': 'MailFilter', 'Extension': 'MailFilterExtension', 'Uninstaller': 'MailFilterUninstaller'}[role],
                PRODUCT_MODULE_NAME={'Host': 'MailFilter', 'Extension': 'MailFilterExtension', 'Uninstaller': 'MailFilterUninstaller'}[role],
                GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE='MacApp/Build/' + template + '-Info.plist',
                CODE_SIGN_ENTITLEMENTS='MacApp/Build/' + entitlement + '.entitlements',
                COMBINE_HIDPI_IMAGES='YES',
                LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/../Frameworks'])
            settings['PRODUCT_BUNDLE_IDENTIFIER'] = ('org.mail-filter.uninstaller' if role == 'Uninstaller'
                else '$(MAIL_FILTER_BUNDLE_ID)' + ('.extension' if role == 'Extension' else ''))
            if role in ('Host', 'Extension'):
                settings['REGISTER_APP_GROUPS'] = 'YES'
            if role == 'Extension':
                settings.update(APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES',
                                OTHER_LDFLAGS=['$(inherited)', '-e', '_NSExtensionMain'])
                if not direct:
                    # App Store validation requires the executable basename to
                    # match the .appex basename. Keep the Swift/ObjC module stable.
                    settings['EXECUTABLE_NAME'] = '$(PRODUCT_NAME)'
            else:
                settings.update(SKIP_INSTALL='NO' if role == 'Host' else 'YES',
                                INSTALL_PATH='$(LOCAL_APPS_DIR)', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon')
        elif role == 'CLI':
            settings.update(PRODUCT_NAME='mail-filter', PRODUCT_MODULE_NAME='MailFilterCLI',
                            SWIFT_VERSION='6.0', SKIP_INSTALL='YES',
                            CODE_SIGN_ENTITLEMENTS='MacApp/Build/CLI.entitlements')
        elif role == 'Helper':
            settings.update(CODE_SIGNING_ALLOWED='NO', CODE_SIGNING_REQUIRED='NO', DEVELOPMENT_TEAM='',
                            CODE_SIGN_IDENTITY='', ENABLE_USER_SCRIPT_SANDBOXING='NO')
        base = ref('MacApp/Build/' + mode + '.xcconfig', 'text.xcconfig')
        values.append(add(name + ':' + mode, 'XCBuildConfiguration', name=mode,
                          baseConfigurationReference=base, buildSettings=settings))
    return add(name, 'XCConfigurationList', buildConfigurations=values,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Local')


doc_paths = ['docs/app-store-deployment-plan', 'docs/dev/architecture', 'docs/dev/getting-started']
docs_phase = add('documentation-phase', 'PBXShellScriptBuildPhase', buildActionMask=2147483647,
    files=[], inputPaths=['$(SRCROOT)/docs/build-docx.py'] + ['$(SRCROOT)/' + p + '.md' for p in doc_paths],
    outputPaths=['$(SRCROOT)/' + p + '.docx' for p in doc_paths],
    name='Regenerate Word documentation', runOnlyForDeploymentPostprocessing=0,
    alwaysOutOfDate=1, showEnvVarsInLog=0, shellPath='/bin/zsh',
    shellScript='set -eu\npython3 "${SRCROOT}/docs/build-docx.py"\n')
add('documentation-target', 'PBXAggregateTarget', name='MailFilterDocumentation',
    productName='MailFilterDocumentation', buildConfigurationList=configs('documentation-configs'),
    dependencies=[], buildPhases=[docs_phase])
embed_file = add('embed-extension-file', 'PBXBuildFile', fileRef=products['extension'],
                 settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
embed = add('embed-extension', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647,
    dstPath='', dstSubfolderSpec=13, files=[embed_file], name='Embed Mail extension', runOnlyForDeploymentPostprocessing=0)
for name, label, role, source_list, resource_list, kind in (
    ('host', 'MailFilter', 'Host', host, resources + [assets, privacy], 'application'),
    ('extension', 'MailFilterExtension', 'Extension', extension, [privacy], 'app-extension'),
    ('uninstaller', 'MailFilterUninstaller', 'Uninstaller', uninstaller, [assets], 'application'),
    ('cli', 'MailFilterCLI', 'CLI', cli, [], 'tool'),
):
    phases = [phase(name + '-sources', 'PBXSourcesBuildPhase', [sources[p] for p in source_list])]
    if resource_list:
        phases.append(phase(name + '-resources', 'PBXResourcesBuildPhase', resource_list))
    if name == 'host':
        phases.append(embed)
    if name == 'extension':
        phases.append(phase('extension-frameworks', 'PBXFrameworksBuildPhase', extension_frameworks))
    add(name + '-target', 'PBXNativeTarget', name=label, productName=label,
        productReference=products[name], productType='com.apple.product-type.' + kind,
        buildConfigurationList=configs(name + '-configs', role),
        dependencies=[dependency('documentation')] + ([dependency('extension')] if name == 'host' else []),
        buildRules=[], buildPhases=phases)

installer_phase = add('local-installer-phase', 'PBXShellScriptBuildPhase', buildActionMask=2147483647,
    files=[], inputPaths=[], outputPaths=[], name='Package built local products',
    runOnlyForDeploymentPostprocessing=0, alwaysOutOfDate=1, showEnvVarsInLog=0, shellPath='/bin/zsh',
    shellScript='set -eu\n[[ "$CONFIGURATION" == Local ]] || { print -u2 "Select the Local installer configuration."; exit 1; }\n'
                '"${SRCROOT}/MacApp/package.sh" local --built-products "${BUILT_PRODUCTS_DIR}"\n')
add('local-installer-target', 'PBXAggregateTarget', name='MailFilterLocalInstaller',
    productName='MailFilterLocalInstaller', buildConfigurationList=configs('installer-configs', 'Helper'),
    dependencies=[dependency(name) for name in ('host', 'cli', 'uninstaller')], buildPhases=[installer_phase])

product_group = add('products', 'PBXGroup', children=list(products.values()), name='Products', sourceTree='<group>')
framework_group = add('frameworks', 'PBXGroup', children=extension_frameworks, name='Frameworks', sourceTree='<group>')
project_configs = configs('project-configs')
# The navigator follows the repository root. Membership is defined above; ignored
# private settings and generated outputs are omitted from this public inventory.
inventory = sorted(set(filter(None, subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0'))))
navigation = {v['path']: key for key, v in objects.items()
              if v['isa'] == 'PBXFileReference' and v.get('sourceTree') == 'SOURCE_ROOT'}
types = {'.swift': 'sourcecode.swift', '.sh': 'text.script.sh', '.py': 'text.script.python',
         '.md': 'net.daringfireball.markdown', '.json': 'text.json', '.txt': 'text',
         '.plist': 'text.plist.xml', '.entitlements': 'text.plist.xml', '.xcconfig': 'text.xcconfig',
         '.xcprivacy': 'text.xml', '.png': 'image.png', '.icns': 'image.icns', '.html': 'text.html',
         '.css': 'text.css', '.yml': 'text.yaml', '.yaml': 'text.yaml'}
for path in inventory:
    if any(part.endswith(('.xcodeproj', '.xcworkspace', '.xcassets')) for part in Path(path).parts):
        continue
    if (ROOT / path).is_file() and path not in navigation:
        kind = types.get(Path(path).suffix, 'file')
        if Path(path).name in ('preinstall', 'postinstall'):
            kind = 'text.script.sh'
        elif Path(path).name in ('.gitignore', '.nojekyll'):
            kind = 'text'
        navigation[path] = ref(path, kind)
tree = {}
for path, key in sorted(navigation.items()):
    branch = tree
    for part in Path(path).parts[:-1]:
        branch = branch.setdefault(part, {})
    branch[Path(path).name] = key


def groups(branch, parts=()):
    children = [groups(child, parts + (name,)) if isinstance(child, dict) else child
                for name, child in sorted(branch.items(), key=lambda x: (not isinstance(x[1], dict), x[0].lower()))]
    if not parts:
        return add('main-group', 'PBXGroup', children=children + [framework_group, product_group], sourceTree='<group>')
    return add('navigation:' + '/'.join(parts), 'PBXGroup', children=children,
               path=parts[-1], sourceTree='<group>')


add('project', 'PBXProject', attributes={'LastUpgradeCheck': '2710', 'BuildIndependentTargetsInParallel': 'YES'},
    buildConfigurationList=project_configs, compatibilityVersion='Xcode 14.0',
    developmentRegion='en', knownRegions=['en', 'Base'], mainGroup=groups(tree),
    productRefGroup=product_group, projectDirPath='', projectRoot='', targets=list(target_ids.values()))


def serialize(value, indent=0):
    prefix = '\t' * indent
    if isinstance(value, dict):
        return '{\n' + ''.join(prefix + '\t' + json.dumps(k) + ' = ' + serialize(v, indent + 1) + ';\n'
                               for k, v in value.items()) + prefix + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(prefix + '\t' + serialize(v, indent + 1) + ',\n' for v in value) + prefix + ')'
    return str(value) if isinstance(value, int) else json.dumps(value)


def buildable(name):
    labels = {'host': ('Mail-Filter.app', 'MailFilter'), 'extension': ('Mail-Filter.appex', 'MailFilterExtension'),
              'uninstaller': ('Uninstall Mail-Filter.app', 'MailFilterUninstaller'), 'cli': ('mail-filter', 'MailFilterCLI'),
              'local-installer': ('MailFilterLocalInstaller', 'MailFilterLocalInstaller')}
    product, label = labels[name]
    return (f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" '
            f'BuildableName="{product}" BlueprintName="{label}" ReferencedContainer="container:Mail-Filter.xcodeproj"/>')


def scheme(configuration, targets, runnable=None, archive=None):
    actions = ''.join('<BuildActionEntry buildForTesting="NO" buildForRunning="YES" '
        f'buildForProfiling="{"YES" if runnable else "NO"}" buildForArchiving="{"YES" if archive else "NO"}" '
        f'buildForAnalyzing="{"NO" if name == "local-installer" else "YES"}">{buildable(name)}</BuildActionEntry>' for name in targets)
    run = f'<BuildableProductRunnable runnableDebuggingMode="0">{buildable(runnable)}</BuildableProductRunnable>' if runnable else ''
    arguments = '<CommandLineArguments><CommandLineArgument argument="--help" isEnabled="YES"/></CommandLineArguments>' if runnable == 'cli' else ''
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>{actions}</BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="{configuration}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES"/>
 <LaunchAction buildConfiguration="{configuration}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO">{run}{arguments}</LaunchAction>
 <ProfileAction buildConfiguration="{configuration}" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">{run}</ProfileAction>
 <AnalyzeAction buildConfiguration="{configuration}"/>
 <ArchiveAction buildConfiguration="{archive or configuration}" revealArchiveInOrganizer="YES"/>
</Scheme>
'''


outputs = {PROJECT / 'project.pbxproj': '// !$*UTF8*$!\n' + serialize(dict(
    archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project_id)) + '\n'}
for name, value in {
    'Mail-Filter Local': scheme('Local', ['host', 'cli', 'uninstaller'], runnable='host'),
    'Mail-Filter Local Installer': scheme('Local', ['local-installer']),
    'Mail-Filter Dev': scheme('Development', ['host'], runnable='host'),
    'Mail-Filter Store': scheme('Development', ['host'], runnable='host', archive='Store'),
    'Mail-Filter Build Check': scheme('BuildCheck', ['host']),
    'mail-filter CLI': scheme('Local', ['cli'], runnable='cli'),
}.items():
    outputs[PROJECT / 'xcshareddata/xcschemes' / (name + '.xcscheme')] = value


def project_matches(actual, expected):
    """Ignore Xcode formatting and redundant labels, but check build semantics."""
    def parse(source):
        value = json.loads(subprocess.check_output(
            ['/usr/bin/plutil', '-convert', 'json', '-o', '-', '-'], input=source.encode(), stderr=subprocess.DEVNULL))
        for obj in value.get('objects', {}).values():
            if obj.get('isa') == 'PBXFileReference' and obj.get('name') == Path(obj.get('path', '')).name:
                obj.pop('name', None)
            if obj.get('isa') == 'PBXProject':
                obj.get('attributes', {}).pop('LastUpgradeCheck', None)
                obj.pop('hasScannedForEncodings', None)
        return value
    try:
        return parse(actual) == parse(expected)
    except (subprocess.CalledProcessError, ValueError):
        return False


def scheme_matches(actual, expected):
    def normalized(source):
        value = ET.fromstring(source)
        value.attrib.pop('LastUpgradeVersion', None)
        return ET.canonicalize(ET.tostring(value, encoding='unicode'), strip_text=True)
    try:
        return normalized(actual) == normalized(expected)
    except ET.ParseError:
        return False


for path, value in outputs.items():
    if '--check' in sys.argv:
        actual = path.read_text() if path.exists() else None
        if actual is not None and path.suffix == '.xcscheme':
            matches = scheme_matches(actual, value)
        elif actual is not None and path.name == 'project.pbxproj':
            matches = project_matches(actual, value)
        else:
            matches = actual == value
        if not matches:
            raise SystemExit('Regenerate root Xcode project: ' + str(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
print('Root Xcode project is current.' if '--check' in sys.argv else 'Generated root Xcode project.')
