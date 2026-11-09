#!/bin/sh
# Run the QML regression tests with the Qt test runner.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

runner=$(command -v qmltestrunner || true)
if [ -z "$runner" ]; then
    for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib/qt5/bin/qmltestrunner; do
        if [ -x "$candidate" ]; then
            runner=$candidate
            break
        fi
    done
fi
if [ -z "$runner" ]; then
    echo "qmltestrunner not found (install the Qt declarative test tools)" >&2
    exit 1
fi

# Headless by default so the tests can run on a machine without a display.
: "${QT_QPA_PLATFORM:=offscreen}"
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR=$(mktemp -d)
fi
# Website card tests load a real page: run Chromium without its sandbox so
# that works in a plain (often containerized) test environment.
: "${QTWEBENGINE_DISABLE_SANDBOX:=1}"
: "${QTWEBENGINE_CHROMIUM_FLAGS:=--no-sandbox --disable-gpu}"
export QT_QPA_PLATFORM XDG_RUNTIME_DIR QTWEBENGINE_DISABLE_SANDBOX QTWEBENGINE_CHROMIUM_FLAGS

exec "$runner" -input "$root/tests/qml" "$@"
