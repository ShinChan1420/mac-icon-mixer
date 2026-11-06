#!/bin/zsh
# Builds the app and writes a drag-to-install disk image. Usage: make-installer.sh [output.dmg]
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build-app.sh

output="${1:-installer/Icon Mixer.dmg}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "build/Icon Mixer.app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$output"
hdiutil create -volname "Icon Mixer" -srcfolder "$staging" -format UDZO -ov "$output"
