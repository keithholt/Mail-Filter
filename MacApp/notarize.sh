#!/bin/zsh
set -eu
root=${0:A:h:h}
package="$root/outputs/Mail-Filter Direct Installer.pkg"
[[ -n "${MAIL_FILTER_NOTARY_PROFILE:-}" ]] || { print -u2 'Set MAIL_FILTER_NOTARY_PROFILE to an existing notarytool Keychain profile.'; exit 1; }
pkgutil --check-signature "$package"
xcrun notarytool submit "$package" --keychain-profile "$MAIL_FILTER_NOTARY_PROFILE" --wait
xcrun stapler staple "$package"
xcrun stapler validate "$package"
spctl --assess --type install --verbose "$package"
print 'Installer signed, notarized and stapled; ready for clean-Mac installation testing.'
