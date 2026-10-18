#!/usr/bin/env python3
"""Compile isolated App Sandbox probes, without installing Mail extensions.

Reports contain fixed statuses, counts and error codes, never email content or
account addresses. Ad-hoc probes cannot establish App Store review approval or
provisioned App Group behavior. Run from a normal Terminal for desktop evidence.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.build/app-store-feasibility'


def run(command, timeout=120):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout,
                          env=dict(os.environ, CLANG_MODULE_CACHE_PATH=str(OUT / 'clang-cache')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mail-metadata', action='store_true', help='Read counts/source length only if Mail automation is already authorized; no consent prompt')
    parser.add_argument('--request-mail-permission', action='store_true', help='Allow macOS to ask for read-only Mail automation permission; implies --mail-metadata')
    parser.add_argument('--synthetic-model', action='store_true', help='Classify one synthetic appeal; never real email')
    parser.add_argument('--all-runtime', action='store_true', help='Try each sandbox variant even if the basic sandbox process cannot launch')
    parser.add_argument('--offline-only', action='store_true', help='Run synthetic routing, migration and activity checks only')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    offline = OUT / 'offline-checks'
    offline_sources = ['Sources/MailFilter/Core.swift', 'MacApp/Shared/MIMEBodyDecoder.swift',
                       'MacApp/Shared/FilteringConfiguration.swift', 'MacApp/Shared/JunkProtection.swift',
                       'MacApp/SharedStore.swift', 'MacApp/Feasibility/OfflineChecks.swift']
    built_offline = run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                         *[str(ROOT / p) for p in offline_sources], '-o', str(offline)])
    if built_offline.returncode:
        print(built_offline.stderr)
        raise SystemExit(built_offline.returncode)
    checked_offline = run([str(offline)])
    print(checked_offline.stdout.strip())
    if checked_offline.returncode:
        print(checked_offline.stderr)
        raise SystemExit(checked_offline.returncode)
    if args.offline_only:
        return
    shared = [
        'Sources/MailFilter/Core.swift', 'Sources/MailFilter/ClassificationRequest.swift',
        'Sources/MailFilter/PoliticalModel.swift', 'MacApp/Shared/MIMEBodyDecoder.swift',
        'MacApp/Shared/FilteringConfiguration.swift', 'MacApp/Shared/JunkProtection.swift',
        'MacApp/Shared/AnalysisDeadline.swift', 'MacApp/Shared/ClassificationRetry.swift', 'MacApp/SharedStore.swift',
        'MacApp/Feasibility/AppStoreProbe.swift',
    ]
    binary = OUT / 'probe'
    compiled = run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-target', 'arm64-apple-macos26.0', *map(lambda p: str(ROOT / p), shared),
                    '-framework', 'AppKit', '-framework', 'ApplicationServices', '-o', str(binary)])
    if compiled.returncode:
        print(compiled.stderr)
        raise SystemExit(compiled.returncode)
    variants = {
        'baseline': {'com.apple.security.automation.apple-events': True},
        'sandbox': {'com.apple.security.app-sandbox': True},
        'compose': {'com.apple.security.app-sandbox': True,
                    'com.apple.security.automation.apple-events': True,
                    'com.apple.security.scripting-targets': {'com.apple.mail': ['com.apple.mail.compose']}},
        'mail-target': {'com.apple.security.app-sandbox': True,
                        'com.apple.security.automation.apple-events': True,
                        'com.apple.security.temporary-exception.apple-events': ['com.apple.mail']},
    }
    report = {'schemaVersion': 1, 'offlineChecksPassed': True, 'compilePassed': True, 'variants': {}}
    basic_sandbox_failed = False
    for name, entitlements in variants.items():
        contents = OUT / (name + '.app') / 'Contents'
        executable = contents / 'MacOS/Feasibility'
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(binary.read_bytes())
        executable.chmod(0o755)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'org.mail-filter.feasibility.' + name,
            'CFBundleExecutable': 'Feasibility', 'CFBundleName': 'Mail Filter Feasibility',
            'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
            'NSAppleEventsUsageDescription': 'Read only Mail account counts and selected message size for compatibility testing.',
        }))
        entitlement_file = OUT / (name + '.entitlements')
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        signed = run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlement_file), str(contents.parent)])
        if signed.returncode:
            raise RuntimeError('Probe signing failed: ' + signed.stderr)
        verified = run(['codesign', '--verify', '--strict', str(contents.parent)])
        displayed = run(['codesign', '-d', '--entitlements', ':-', str(contents.parent)])
        actual_entitlements = plistlib.loads(displayed.stdout.encode())
        result = {'signatureVerified': verified.returncode == 0,
                  'entitlementsVerified': actual_entitlements == entitlements,
                  'sandboxDeclared': bool(entitlements.get('com.apple.security.app-sandbox'))}
        if not result['signatureVerified'] or not result['entitlementsVerified']:
            raise RuntimeError('Probe signature or entitlement verification failed')
        if basic_sandbox_failed and name not in ('baseline', 'sandbox') and not args.all_runtime:
            result['runtime'] = 'notRunBasicSandboxLaunchFailed'
        else:
            command = [str(executable)]
            if args.mail_metadata or args.request_mail_permission:
                command += ['--mail-metadata']
            if args.request_mail_permission:
                command += ['--request-mail-permission']
            if args.synthetic_model:
                command += ['--synthetic-model']
            try:
                process = run(command, timeout=35)
                result['exitCode'] = process.returncode
                lines = [line for line in process.stdout.splitlines() if line.startswith('{')]
                if lines:
                    result['observations'] = json.loads(lines[-1])
                    result['runtime'] = 'completed'
                else:
                    result['runtime'] = 'noStructuredResult'
                    if name == 'sandbox':
                        basic_sandbox_failed = True
            except subprocess.TimeoutExpired:
                result['runtime'] = 'timedOut'
                if name == 'sandbox':
                    basic_sandbox_failed = True
        report['variants'][name] = result
        print(name + ': ' + result['runtime'])
    destination = OUT / 'results.json'
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print('Report: .build/app-store-feasibility/results.json')
    print('Ad-hoc runtime results do not establish App Group provisioning or App Review approval.')


if __name__ == '__main__':
    main()
