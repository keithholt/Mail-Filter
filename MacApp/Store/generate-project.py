#!/usr/bin/env python3
"""Generate the checked-in Xcode archive project using only Python's stdlib."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PROJECT = HERE / 'Mail-Filter.xcodeproj'
objects = {}


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(key_name, isa, **values):
    key = uid(key_name)
    objects[key] = dict(isa=isa, **values)
    return key


def ref(path, kind):
    return add('file:' + path, 'PBXFileReference', lastKnownFileType=kind, name=Path(path).name, path=path, sourceTree='SOURCE_ROOT')


def phase(name, isa, files, **extra):
    built = [add(name + ':' + f, 'PBXBuildFile', fileRef=f) for f in files]
    return add(name, isa, buildActionMask=2147483647, files=built, runOnlyForDeploymentPostprocessing=0, **extra)


shared = [
    'Sources/MailFilter/Core.swift', 'Sources/MailFilter/ClassificationRequest.swift',
    'Sources/MailFilter/PoliticalModel.swift', 'MacApp/SharedStore.swift',
    'MacApp/Shared/MIMEBodyDecoder.swift', 'MacApp/Shared/FilteringConfiguration.swift',
    'MacApp/Shared/JunkProtection.swift', 'MacApp/Shared/AnalysisDeadline.swift',
    'MacApp/Shared/ClassificationRetry.swift',
]
host = shared + ['Sources/MailFilter/MailAutomation.swift'] + [
    'MacApp/' + n + '.swift' for n in ('MailFilterApp', 'SettingsModel', 'SettingsView',
    'AccountInventory', 'MessageDiagnostics', 'SelectedEmailReport', 'DiagnosticReport')]
extension = shared + ['MacApp/' + n + '.swift' for n in (
    'NativeClassifier', 'NativeExtension', 'Shared/InspectionScheduler', 'Shared/BodyRequestTracker')]
source_refs = {p: ref('../../' + p, 'sourcecode.swift') for p in sorted(set(host + extension))}
resources = [ref('../Resources/' + n, 'text') for n in ('filter.txt', 'political-evidence.txt')]
resources.append(ref('Assets.xcassets', 'folder.assetcatalog'))
privacy = ref('PrivacyInfo.xcprivacy', 'text.xml')
host_product = add('host-product', 'PBXFileReference', explicitFileType='wrapper.application',
                   path='Mail-Filter.app', sourceTree='BUILT_PRODUCTS_DIR')
extension_product = add('extension-product', 'PBXFileReference', explicitFileType='wrapper.app-extension',
                        path='Mail-Filter.appex', sourceTree='BUILT_PRODUCTS_DIR')
host_target = uid('host-target')
extension_target = uid('extension-target')
installer_target = uid('local-installer-target')
project_id = uid('project')
proxy = add('extension-proxy', 'PBXContainerItemProxy', containerPortal=project_id,
            proxyType=1, remoteGlobalIDString=extension_target, remoteInfo='MailFilterExtension')
dependency = add('extension-dependency', 'PBXTargetDependency', target=extension_target, targetProxy=proxy)
embed_file = add('embed-extension-file', 'PBXBuildFile', fileRef=extension_product,
                 settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
embed = add('embed-extension', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647,
            dstPath='', dstSubfolderSpec=13, files=[embed_file], name='Embed Mail extension', runOnlyForDeploymentPostprocessing=0)


def configs(name, target=None, packaging=False):
    configs = []
    for mode in ('BuildCheck', 'Development', 'Store'):
        settings = {'SDKROOT': 'macosx', 'MACOSX_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64',
                    'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'CODE_SIGN_STYLE': 'Automatic',
                    'ENABLE_HARDENED_RUNTIME': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'APP_STORE',
                    'MARKETING_VERSION': '2.1.0', 'CURRENT_PROJECT_VERSION': '14',
                    'SWIFT_OPTIMIZATION_LEVEL': '-O' if mode == 'Store' else '-Onone',
                    'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'}
        if packaging:
            # The existing packager writes repo outputs and a Desktop shortcut.
            # Only this explicit helper target may run outside Xcode's script sandbox.
            settings.update(CODE_SIGNING_ALLOWED='NO', CODE_SIGNING_REQUIRED='NO',
                            CODE_SIGN_IDENTITY='', DEVELOPMENT_TEAM='', ENABLE_USER_SCRIPT_SANDBOXING='NO')
        if target:
            settings.update(PRODUCT_NAME='Mail-Filter', GENERATE_INFOPLIST_FILE='NO',
                            INFOPLIST_FILE=target + '-Info.plist', CODE_SIGN_ENTITLEMENTS=target + '.entitlements',
                            COMBINE_HIDPI_IMAGES='YES', LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/../Frameworks'])
            settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(MAIL_FILTER_BUNDLE_ID)' + ('.extension' if target == 'Extension' else '')
            if target == 'Extension':
                settings.update(PRODUCT_MODULE_NAME='MailFilterExtension', APPLICATION_EXTENSION_API_ONLY='YES',
                                SKIP_INSTALL='YES', OTHER_LDFLAGS=['$(inherited)', '-e', '_NSExtensionMain'])
            else:
                settings.update(SKIP_INSTALL='NO', INSTALL_PATH='$(LOCAL_APPS_DIR)', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon')
        config_ref = ref(mode + '.xcconfig', 'text.xcconfig')
        configs.append(add(name + ':' + mode, 'XCBuildConfiguration', name=mode,
                           baseConfigurationReference=config_ref, buildSettings=settings))
    return add(name, 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Development')


add('host-target', 'PBXNativeTarget', name='MailFilter', productName='Mail-Filter',
    productReference=host_product, productType='com.apple.product-type.application',
    buildConfigurationList=configs('host-configs', 'Host'), dependencies=[dependency], buildRules=[],
    buildPhases=[phase('host-sources', 'PBXSourcesBuildPhase', [source_refs[p] for p in host]),
                 phase('host-resources', 'PBXResourcesBuildPhase', resources + [privacy]), embed])
add('extension-target', 'PBXNativeTarget', name='MailFilterExtension', productName='Mail-Filter',
    productReference=extension_product, productType='com.apple.product-type.app-extension',
    buildConfigurationList=configs('extension-configs', 'Extension'), dependencies=[], buildRules=[],
    buildPhases=[phase('extension-sources', 'PBXSourcesBuildPhase', [source_refs[p] for p in extension]),
                 phase('extension-resources', 'PBXResourcesBuildPhase', [privacy])])
installer_phase = add('local-installer-phase', 'PBXShellScriptBuildPhase',
                      buildActionMask=2147483647, files=[], inputPaths=[], outputPaths=[],
                      name='Build and verify local installer', runOnlyForDeploymentPostprocessing=0,
                      alwaysOutOfDate=1, showEnvVarsInLog=0, shellPath='/bin/zsh',
                      shellScript='set -eu\nexport MAIL_FILTER_SIGN_IDENTITY="-"\n"${SRCROOT}/../package.sh" local\n')
add('local-installer-target', 'PBXAggregateTarget', name='MailFilterLocalInstaller',
    productName='MailFilterLocalInstaller', buildConfigurationList=configs('installer-configs', packaging=True),
    dependencies=[], buildPhases=[installer_phase])
products = add('products', 'PBXGroup', children=[host_product, extension_product], name='Products', sourceTree='<group>')
configuration_files = [ref(mode + '.xcconfig', 'text.xcconfig') for mode in ('BuildCheck', 'Development', 'Store')]
configuration_files += [ref('Signing.example.xcconfig', 'text.xcconfig'), ref('README.md', 'net.daringfireball.markdown')]
configuration_group = add('configuration-group', 'PBXGroup', children=configuration_files,
                          name='Build Configuration', sourceTree='<group>')

# Show the public repository layout, including developer-only files, without
# making them target members. Source/resource build phases above remain explicit.
# Git's inventory excludes private configuration, caches and generated outputs.
public_files = sorted(set(filter(None, subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0'))))
navigation_refs = {}
for key, value in list(objects.items()):
    if value['isa'] == 'PBXFileReference' and value.get('sourceTree') == 'SOURCE_ROOT':
        path = (HERE / value['path']).resolve()
        navigation_refs[path.relative_to(ROOT).as_posix()] = key
types = {'.swift': 'sourcecode.swift', '.sh': 'text.script.sh', '.py': 'text.script.python',
         '.md': 'net.daringfireball.markdown', '.json': 'text.json', '.txt': 'text',
         '.plist': 'text.plist.xml', '.entitlements': 'text.plist.xml', '.xcconfig': 'text.xcconfig',
         '.xcprivacy': 'text.xml', '.png': 'image.png'}
for path in public_files:
    if not path or '.xcodeproj/' in path or '.xcworkspace/' in path or '.xcassets/' in path:
        continue
    if (ROOT / path).is_file() and path not in navigation_refs:
        navigation_refs[path] = ref('../../' + path, types.get(Path(path).suffix, 'file'))
tree = {}
for path, key in sorted(navigation_refs.items()):
    if key in configuration_files:
        continue  # These remain in the convenient Build Configuration group.
    branch = tree
    parts = Path(path).parts
    for part in parts[:-1]:
        branch = branch.setdefault(part, {})
    branch[parts[-1]] = key


def navigation_group(branch, parts=()):
    children = []
    for name, child in sorted(branch.items(), key=lambda item: (not isinstance(item[1], dict), item[0].lower())):
        children.append(navigation_group(child, parts + (name,)) if isinstance(child, dict) else child)
    return add('navigation:' + '/'.join(parts), 'PBXGroup', children=children,
               name=parts[-1] if parts else 'Repository', path='../../' + '/'.join(parts), sourceTree='SOURCE_ROOT')


repository_group = navigation_group(tree)
main_group = add('main-group', 'PBXGroup', children=[repository_group, configuration_group, products], sourceTree='<group>')
add('project', 'PBXProject', attributes={'LastUpgradeCheck': '2700'}, buildConfigurationList=configs('project-configs'),
    compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'Base'],
    mainGroup=main_group, productRefGroup=products, projectDirPath='', projectRoot='',
    targets=[host_target, extension_target, installer_target])


def serialize(value, indent=0):
    prefix = '\t' * indent
    if isinstance(value, dict):
        return '{\n' + ''.join(prefix + '\t' + json.dumps(k) + ' = ' + serialize(v, indent + 1) + ';\n' for k, v in value.items()) + prefix + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(prefix + '\t' + serialize(v, indent + 1) + ',\n' for v in value) + prefix + ')'
    return str(value) if isinstance(value, int) else json.dumps(value)


payload = '// !$*UTF8*$!\n' + serialize(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project_id)) + '\n'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{host_target}" BuildableName="Mail-Filter.app" BlueprintName="MailFilter" ReferencedContainer="container:Mail-Filter.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Development" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES"/>
 <LaunchAction buildConfiguration="Development" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{host_target}" BuildableName="Mail-Filter.app" BlueprintName="MailFilter" ReferencedContainer="container:Mail-Filter.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Development" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Development"/>
 <ArchiveAction buildConfiguration="Store" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
outputs = {PROJECT / 'project.pbxproj': payload,
           PROJECT / 'xcshareddata/xcschemes/Mail-Filter.xcscheme': scheme}
outputs[PROJECT / 'xcshareddata/xcschemes/Mail-Filter Build Check.xcscheme'] = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{host_target}" BuildableName="Mail-Filter.app" BlueprintName="MailFilter" ReferencedContainer="container:Mail-Filter.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="BuildCheck" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES"/>
 <!-- Build uses the Run configuration. Deliberately omit a runnable for unsigned products. -->
 <LaunchAction buildConfiguration="BuildCheck" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"/>
 <ProfileAction buildConfiguration="BuildCheck" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="BuildCheck"/>
 <ArchiveAction buildConfiguration="BuildCheck" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
outputs[PROJECT / 'xcshareddata/xcschemes/Mail-Filter Local Installer.xcscheme'] = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
 <BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{installer_target}" BuildableName="MailFilterLocalInstaller" BlueprintName="MailFilterLocalInstaller" ReferencedContainer="container:Mail-Filter.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="BuildCheck" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES"/>
 <!-- Build invokes packaging only; there is no app or installer executable to launch. -->
 <LaunchAction buildConfiguration="BuildCheck" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"/>
 <ProfileAction buildConfiguration="BuildCheck" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="BuildCheck"/>
 <ArchiveAction buildConfiguration="BuildCheck" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
for path, value in outputs.items():
    if '--check' in sys.argv:
        actual = path.read_text() if path.exists() else None
        # Xcode reformats shared schemes when saving them. Compare XML structure
        # so formatting changes pass while changed actions/settings still fail.
        if actual is not None and path.suffix == '.xcscheme':
            try:
                matches = ET.canonicalize(actual, strip_text=True) == ET.canonicalize(value, strip_text=True)
            except ET.ParseError:
                matches = False
        else:
            matches = actual == value
        if not matches:
            raise SystemExit('Regenerate Store Xcode project: ' + str(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
print('Store Xcode project is current.' if '--check' in sys.argv else 'Generated Store Xcode project.')
