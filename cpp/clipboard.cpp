#include <QtCore/qbuffer.h>
#include <QtCore/qbytearray.h>
#include <QtCore/qmimedata.h>
#include <QtCore/qstring.h>
#include <QtGui/qclipboard.h>
#include <QtGui/qguiapplication.h>
#include <QtGui/qimage.h>

#include <cstdlib>
#include <cstring>

namespace {

unsigned char *copy_bytes(const QByteArray &data, int *out_len)
{
    if (data.isEmpty()) {
        return nullptr;
    }
    auto *buffer = static_cast<unsigned char *>(std::malloc(static_cast<size_t>(data.size())));
    if (!buffer) {
        return nullptr;
    }
    std::memcpy(buffer, data.constData(), static_cast<size_t>(data.size()));
    if (out_len) {
        *out_len = data.size();
    }
    return buffer;
}

} // namespace

extern "C" unsigned char *corcho_clipboard_text(int *out_len)
{
    if (out_len) {
        *out_len = 0;
    }
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        return nullptr;
    }
    const QString text = clipboard->text();
    if (text.isEmpty()) {
        return nullptr;
    }
    return copy_bytes(text.toUtf8(), out_len);
}

extern "C" unsigned char *corcho_clipboard_image_png(int *out_len, int *out_width, int *out_height)
{
    if (out_len) {
        *out_len = 0;
    }
    if (out_width) {
        *out_width = 0;
    }
    if (out_height) {
        *out_height = 0;
    }
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        return nullptr;
    }
    const QMimeData *mime = clipboard->mimeData();
    if (!mime || !mime->hasImage()) {
        return nullptr;
    }
    const QImage image = clipboard->image();
    if (image.isNull()) {
        return nullptr;
    }
    QByteArray png;
    QBuffer buffer(&png);
    if (!buffer.open(QIODevice::WriteOnly)) {
        return nullptr;
    }
    if (!image.save(&buffer, "PNG")) {
        return nullptr;
    }
    buffer.close();
    if (out_width) {
        *out_width = image.width();
    }
    if (out_height) {
        *out_height = image.height();
    }
    return copy_bytes(png, out_len);
}

extern "C" int corcho_clipboard_set_text(const unsigned char *data, int len)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard || (!data && len > 0) || len < 0) {
        return 0;
    }
    const QString text = QString::fromUtf8(reinterpret_cast<const char *>(data), len);
    clipboard->setText(text, QClipboard::Clipboard);
    return 1;
}

extern "C" void corcho_clipboard_free(unsigned char *buffer)
{
    std::free(buffer);
}
