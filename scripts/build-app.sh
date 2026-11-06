#!/bin/zsh
# Builds build/Icon Mixer.app. Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "${0:A:h}/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release

app="build/Icon Mixer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/IconMixer" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - "$app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "$HOME/Applications/Icon Mixer.app"
    cp -R "$app" "$HOME/Applications/"
    echo "Installed to ~/Applications/Icon Mixer.app"
fi
