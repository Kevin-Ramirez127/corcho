import QtQuick

Item {
    id: root

    property var app
    property var th
    property var cards: []
    property real viewportWidth: 800
    property real viewportHeight: 600
    property int minimapWidth: 176
    property int minimapHeight: 112

    signal centerAt(real worldX, real worldY)

    width: minimapWidth
    height: minimapHeight

    readonly property var bounds: {
        var minX = 0, minY = 0, maxX = viewportWidth, maxY = viewportHeight;
        var w = viewportWidth / Math.max(0.2, root.app.zoom);
        var h = viewportHeight / Math.max(0.2, root.app.zoom);
        minX = -root.app.panX / Math.max(0.2, root.app.zoom);
        minY = -root.app.panY / Math.max(0.2, root.app.zoom);
        maxX = minX + w;
        maxY = minY + h;
        for (var i = 0; i < cards.length; i++) {
            var c = cards[i];
            minX = Math.min(minX, c.x);
            minY = Math.min(minY, c.y);
            maxX = Math.max(maxX, c.x + c.width);
            maxY = Math.max(maxY, c.y + c.height);
        }
        var pad = 80;
        return { x: minX - pad, y: minY - pad, w: Math.max(1, maxX - minX + pad * 2), h: Math.max(1, maxY - minY + pad * 2) };
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.th.menu
        border.width: 1
        border.color: root.th.border
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 8
        property var b: root.bounds
        onBChanged: requestPaint()
        Connections {
            target: root.app
            function onPanXChanged() { canvas.requestPaint(); }
            function onPanYChanged() { canvas.requestPaint(); }
            function onZoomChanged() { canvas.requestPaint(); }
        }
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var b = root.bounds;
            var sx = width / b.w;
            var sy = height / b.h;
            var s = Math.min(sx, sy);
            var ox = (width - b.w * s) / 2;
            var oy = (height - b.h * s) / 2;
            function px(x) { return ox + (x - b.x) * s; }
            function py(y) { return oy + (y - b.y) * s; }

            for (var i = 0; i < root.cards.length; i++) {
                var c = root.cards[i];
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.16);
                ctx.fillRect(px(c.x), py(c.y), Math.max(1, c.width * s), Math.max(1, c.height * s));
            }

            var z = Math.max(0.2, root.app.zoom);
            var vx = -root.app.panX / z;
            var vy = -root.app.panY / z;
            var vw = root.viewportWidth / z;
            var vh = root.viewportHeight / z;
            ctx.strokeStyle = root.th.accent;
            ctx.lineWidth = 1.2;
            ctx.strokeRect(px(vx), py(vy), Math.max(1, vw * s), Math.max(1, vh * s));
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function (mouse) {
                var b = root.bounds;
                var s = Math.min(width / b.w, height / b.h);
                var ox = (width - b.w * s) / 2;
                var oy = (height - b.h * s) / 2;
                var wx = b.x + (mouse.x - ox) / s;
                var wy = b.y + (mouse.y - oy) / s;
                root.centerAt(wx, wy);
            }
        }
    }
}
