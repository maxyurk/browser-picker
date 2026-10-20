#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
for installed in '/Applications/Browser Picker.app' "$HOME/Applications/Browser Picker.app"; do
    if [[ -e "$installed" ]]; then
        printf '%s\n' "Browser Picker is already installed at $installed. Quit and replace that copy instead of creating another installation."
        exit 1
    fi
done
./scripts/build.sh release
destination='/Applications/Browser Picker.app'
if [[ ! -w /Applications ]]; then
    destination="$HOME/Applications/Browser Picker.app"
    mkdir -p "$HOME/Applications"
fi
ditto "build/Browser Picker.app" "$destination"
open "$destination"
