#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

install=false
for arg in "$@"; do
  case "$arg" in
    --install) install=true ;;
    *) echo "usage: $0 [--install]" >&2; exit 2 ;;
  esac
done

swift build -c release
bin="$(swift build -c release --show-bin-path)/Memmap"

app=memmap.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/memmap"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $PWD/$app"

if $install; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$app"
  cp -R "$app" "$HOME/Applications/$app"
  echo "Installed $HOME/Applications/$app"
fi
