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
export QT_QPA_PLATFORM XDG_RUNTIME_DIR

exec "$runner" -input "$root/tests/qml" "$@"
