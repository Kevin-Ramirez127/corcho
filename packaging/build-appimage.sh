#!/usr/bin/env bash
# Build a Corcho AppImage. Requires linuxdeploy + its Qt plugin on PATH, or set
# LINUXDEPLOY to the binary. Qt is bundled by the plugin; no CMake needed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APPDIR="$ROOT/target/AppDir"
OUT="$ROOT/target"

QMAKE="${QMAKE:-qmake6}" cargo build --release

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/scalable/apps"

install -m755 target/release/corcho "$APPDIR/usr/bin/corcho"
install -m644 packaging/corcho.desktop "$APPDIR/usr/share/applications/"
install -m644 packaging/corcho.svg "$APPDIR/usr/share/icons/hicolor/scalable/apps/corcho.svg"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
exec "$HERE/usr/bin/corcho" "$@"
EOF
chmod +x "$APPDIR/AppRun"

LD="${LINUXDEPLOY:-linuxdeploy}"
if ! command -v "$LD" >/dev/null 2>&1; then
  echo "linuxdeploy not found. Download it and its Qt plugin:" >&2
  echo "  https://github.com/linuxdeploy/linuxdeploy/releases" >&2
  echo "  https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases" >&2
  echo "Then rerun with LINUXDEPLOY=/path/to/linuxdeploy." >&2
  exit 1
fi

"$LD" --appdir "$APPDIR" \
  --plugin qt \
  --desktop-file "$APPDIR/usr/share/applications/corcho.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/scalable/apps/corcho.svg" \
  --output appimage

mv ./*.AppImage "$OUT/" 2>/dev/null || true
echo "AppImage written to $OUT"
