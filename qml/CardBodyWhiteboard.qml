import QtQuick

CardFrame {
    id: root

    property var strokes: []
    property string penColor: root.th ? root.th.accent : "#d98e5c"
    property real penWidth: 3
    property string tool: "draw"
    property var current: []
    property bool drawing: false
    property bool erasing: false
    property bool eraseDirty: false
    readonly property real eraserRadius: 10

    function syncFromCard() {
        if (!root.card) return;
        root.strokes = root.card.strokes ? root.card.strokes : [];
        root.penColor = root.card.penColor ? root.card.penColor : (root.th ? root.th.accent : "#d98e5c");
        root.penWidth = (root.card.penWidth !== undefined && root.card.penWidth !== null) ? root.card.penWidth : 3;
    }

    Component.onCompleted: root.syncFromCard()
    onCardChanged: root.syncFromCard()
    // Keep the default pen colour following the theme until the card stores one.
    onThChanged: {
        if (root.card && !root.card.penColor)
            root.penColor = root.th ? root.th.accent : "#d98e5c";
    }

    function persist() {
        root.commit({ strokes: root.strokes, penColor: root.penColor, penWidth: root.penWidth });
    }

    function distanceToSegmentSq(px, py, ax, ay, bx, by) {
        var dx = bx - ax;
        var dy = by - ay;
        if (dx === 0 && dy === 0) {
            dx = px - ax;
            dy = py - ay;
            return dx * dx + dy * dy;
        }
        var t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
        t = Math.max(0, Math.min(1, t));
        var x = ax + t * dx;
        var y = ay + t * dy;
        dx = px - x;
        dy = py - y;
        return dx * dx + dy * dy;
    }

    // Strokes are independent, so touching any part of a stroke erases that
    // whole stroke. Everything overlapping the eraser point goes with it.
    function strokeHit(stroke, x, y) {
        var points = stroke && stroke.points ? stroke.points : [];
        if (points.length === 0) return false;
        var radius = root.eraserRadius + ((stroke.width || root.penWidth) / 2);
        var radiusSq = radius * radius;
        if (points.length === 1) {
            var ox = x - points[0].x;
            var oy = y - points[0].y;
            return ox * ox + oy * oy <= radiusSq;
        }
        for (var i = 1; i < points.length; i++) {
            if (root.distanceToSegmentSq(
                    x, y,
                    points[i - 1].x, points[i - 1].y,
                    points[i].x, points[i].y) <= radiusSq)
                return true;
        }
        return false;
    }

    function eraseAt(x, y) {
        var next = [];
        var removed = false;
        for (var i = 0; i < root.strokes.length; i++) {
            if (root.strokeHit(root.strokes[i], x, y)) {
                removed = true;
            } else {
                next.push(root.strokes[i]);
            }
        }
        if (removed) {
            root.strokes = next;
            canvas.requestPaint();
        }
        return removed;
    }

    onStrokesChanged: canvas.requestPaint()

    Column {
        anchors.fill: parent
        spacing: root.th.spaceCompact
        Row {
            spacing: root.th.spaceCompact
            Repeater {
                model: [root.th.accent, root.th.text, "#86b78a", "#7aa2f7", root.th.danger]

                delegate: Item {
                    required property var modelData
                    width: 16
                    height: 16

                    Rectangle {
                        anchors.fill: parent
                        radius: root.th.radiusControl
                        color: modelData
                        border.width: root.penColor === modelData ? 2 : 0
                        border.color: root.th.text
                    }
                    TapHandler {
                        onTapped: {
                            root.penColor = modelData;
                            root.tool = "draw";
                            root.persist();
                        }
                    }
                }
            }

            Item { width: 6; height: 1 }

            Icon {
                name: "pencil"
                size: root.th.iconBody
                color: root.tool === "draw" ? root.th.accent : root.th.muted
                TapHandler {
                    onTapped: root.tool = "draw"
                }
            }

            Icon {
                name: "eraser"
                size: root.th.iconBody
                color: root.tool === "erase" ? root.th.accent : root.th.muted
                TapHandler {
                    onTapped: root.tool = "erase"
                }
            }

            Item { width: 6; height: 1 }

            Icon {
                name: "trash-2"
                size: root.th.iconBody
                color: root.th.muted
                TapHandler {
                    onTapped: {
                        root.strokes = [];
                        root.persist();
                        canvas.requestPaint();
                    }
                }
            }
        }

        Canvas {
            id: canvas
            width: parent.width
            height: parent.height - 26
            renderStrategy: Canvas.Cooperative

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                for (var i = 0; i < root.strokes.length; i++) {
                    var s = root.strokes[i];
                    if (!s.points || s.points.length < 2) continue;
                    ctx.strokeStyle = s.color || root.penColor;
                    ctx.lineWidth = s.width || root.penWidth;
                    ctx.beginPath();
                    ctx.moveTo(s.points[0].x, s.points[0].y);
                    for (var j = 1; j < s.points.length; j++) ctx.lineTo(s.points[j].x, s.points[j].y);
                    ctx.stroke();
                }
                if (root.current.length > 1) {
                    ctx.strokeStyle = root.penColor;
                    ctx.lineWidth = root.penWidth;
                    ctx.beginPath();
                    ctx.moveTo(root.current[0].x, root.current[0].y);
                    for (var k = 1; k < root.current.length; k++) ctx.lineTo(root.current[k].x, root.current[k].y);
                    ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: root.tool === "erase" ? Qt.CrossCursor : Qt.ArrowCursor
                onPressed: function (mouse) {
                    if (root.tool === "erase") {
                        root.erasing = true;
                        root.eraseDirty = false;
                        if (root.eraseAt(mouse.x, mouse.y)) root.eraseDirty = true;
                        return;
                    }
                    root.current = [{ x: mouse.x, y: mouse.y }];
                    root.drawing = true;
                }
                onPositionChanged: function (mouse) {
                    if (root.tool === "erase") {
                        if (!root.erasing) return;
                        if (root.eraseAt(mouse.x, mouse.y)) root.eraseDirty = true;
                        return;
                    }
                    if (!root.drawing) return;
                    root.current.push({ x: mouse.x, y: mouse.y });
                    canvas.requestPaint();
                }
                onReleased: {
                    if (root.tool === "erase") {
                        if (!root.erasing) return;
                        root.erasing = false;
                        if (root.eraseDirty) {
                            root.eraseDirty = false;
                            root.persist();
                        }
                        return;
                    }
                    if (!root.drawing) return;
                    root.drawing = false;
                    if (root.current.length > 1) {
                        var next = root.strokes.slice();
                        next.push({ color: root.penColor, width: root.penWidth, points: root.current });
                        root.strokes = next;
                        root.current = [];
                        root.persist();
                    } else {
                        root.current = [];
                    }
                    canvas.requestPaint();
                }
                onCanceled: {
                    root.drawing = false;
                    root.erasing = false;
                    root.eraseDirty = false;
                    root.current = [];
                    canvas.requestPaint();
                }
            }
        }
    }
}
