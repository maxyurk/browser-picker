#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh release
destination="$HOME/Applications/Browser Picker.app"
mkdir -p "$HOME/Applications"
if [[ -e "$destination" ]]; then
    printf '%s\n' "An installed copy already exists at $destination. Quit it before replacing it."
    exit 1
fi
ditto "build/Browser Picker.app" "$destination"
open "$destination"
