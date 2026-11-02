#!/usr/bin/env bash
# Build a Debian package that depends on the system Qt 6 stack.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"
ARCH="$(dpkg --print-architecture)"
PKG="$ROOT/target/deb/corcho_${VERSION}_${ARCH}"
OUT="$ROOT/target/corcho_${VERSION}_${ARCH}.deb"

QMAKE="${QMAKE:-qmake6}" cargo build --release

rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/usr/bin" \
         "$PKG/usr/share/applications" \
         "$PKG/usr/share/icons/hicolor/scalable/apps"

install -m755 target/release/corcho "$PKG/usr/bin/corcho"
install -m644 packaging/corcho.desktop "$PKG/usr/share/applications/"
install -m644 packaging/corcho.svg "$PKG/usr/share/icons/hicolor/scalable/apps/corcho.svg"

cat > "$PKG/DEBIAN/control" <<EOF
Package: corcho
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Corcho contributors <corcho@localhost>
Depends: libc6, libstdc++6, libqt6core6, libqt6gui6, libqt6qml6, libqt6quick6, libqt6quickcontrols2-6, libqt6svg6, libqt6webenginequick6, libqt6webenginecore6, libqt6network6, libasound2
Description: A native grid workspace for notes, sites, tasks and calendars
 Corcho is an infinite canvas for notes, websites, tasks, timers and
 calendars. Rust core, Qt 6 interface.
EOF

dpkg-deb --build --root-owner-group "$PKG" "$OUT"
echo "Debian package written to $OUT"
