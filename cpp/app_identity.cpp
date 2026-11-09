#include <QtCore/qcoreapplication.h>
#include <QtCore/qstring.h>
#include <QtGui/qguiapplication.h>

// Give the process a stable Wayland app_id / X11 WM_CLASS so compositor
// window rules (sway, Hyprland, …) can match Corcho windows.
//
// Qt derives the Wayland app_id from QGuiApplication::desktopFileName().
// Flatpak builds use the reverse-DNS application id, native installs use the
// desktop entry name shipped in packaging/.
extern "C" void corcho_set_app_identity()
{
    const QString flatpakId = QString::fromUtf8(qgetenv("FLATPAK_ID"));
    const QString desktopFile = flatpakId.isEmpty() ? QStringLiteral("corcho") : flatpakId;

    QGuiApplication::setDesktopFileName(desktopFile);
    QGuiApplication::setApplicationName(QStringLiteral("corcho"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Corcho"));
}
