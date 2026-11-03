#include <QtCore/qlogging.h>
#include <QtCore/qbytearray.h>
#include <QtCore/qstring.h>

extern "C" void corcho_log_message(int type, const char *message);

static QtMessageHandler previous_handler = nullptr;

static void corcho_message_handler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    const QByteArray utf8 = message.toUtf8();
    corcho_log_message(static_cast<int>(type), utf8.constData());
    if (previous_handler) {
        previous_handler(type, context, message);
    }
}

extern "C" void corcho_install_log_handler()
{
    previous_handler = qInstallMessageHandler(corcho_message_handler);
}
