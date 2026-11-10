import QtQuick

CardFrame {
    id: root

    property var strokes: []
    property string penColor: root.th ? root.th.accent : "#d98e5c"
    property real penWidth: 3
    property alias clearMenuPopup: clearMenu
    property string tool: "draw"
    property var current: []
    property bool drawing: false
    property bool erasing: false
    property bool eraseDirty: false
    readonly property real eraserRadius: 10
    // Pointer position in canvas coordinates, tracked by the handlers below.
    property point cursorPos: Qt.point(0, 0)
    // True only while the pointer is actually over the drawing canvas, so the
    // custom cursor disappears as soon as it leaves the drawing area.
    readonly property bool cursorInside: (hoverHandler.hovered || drawHandler.active)
        && cursorPos.x >= 0 && cursorPos.x <= canvas.width
        && cursorPos.y >= 0 && cursorPos.y <= canvas.height
    // Stylus pressure is opt-out, so workspaces saved before the setting
    // existed keep pressure sensitivity enabled.
    readonly property bool pressureEnabled:
        !root.settings || root.settings.whiteboard_pressure !== false
    // The card's drag handler is what normally owns the cursor, so it has to
    // blank it out too while the drawing cursor is shown.
    dragCursorShape: root.cursorInside ? Qt.BlankCursor : Qt.SizeAllCursor
    onCursorInsideChanged: {
        if (root.canvasView) root.canvasView.hidePointer = root.cursorInside;
    }
    Component.onDestruction: {
        if (root.canvasView) root.canvasView.hidePointer = false;
    }

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

    function clearContent() {
        root.strokes = [];
        root.persist();
        canvas.requestPaint();
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

    // Only pen and eraser tips carry meaningful pressure. Mouse and touch
    // input keeps the original flat stroke width.
    function isStylus(point) {
        if (!point || !point.device) return false;
        var type = point.device.pointerType;
        return type === PointerDevice.Pen || type === PointerDevice.Eraser;
    }

    function pointPressure(point) {
        if (!root.pressureEnabled || !root.isStylus(point)) return 1;
        var pressure = Number(point.pressure);
        if (!isFinite(pressure) || pressure <= 0) return 1;
        return Math.min(1, pressure);
    }

    function updateCursor(point) {
        if (!point) return;
        root.cursorPos = Qt.point(point.position.x, point.position.y);
    }

    function beginStroke(point) {
        root.updateCursor(point);
        if (root.tool === "erase") {
            root.erasing = true;
            root.eraseDirty = false;
            if (root.eraseAt(point.position.x, point.position.y)) root.eraseDirty = true;
            return;
        }
        root.current = [{ x: point.position.x, y: point.position.y, p: root.pointPressure(point) }];
        root.drawing = true;
    }

    function extendStroke(point) {
        root.updateCursor(point);
        if (root.tool === "erase") {
            if (!root.erasing) return;
            if (root.eraseAt(point.position.x, point.position.y)) root.eraseDirty = true;
            return;
        }
        if (!root.drawing) return;
        var last = root.current.length > 0 ? root.current[root.current.length - 1] : null;
        if (last && last.x === point.position.x && last.y === point.position.y) return;
        root.current.push({ x: point.position.x, y: point.position.y, p: root.pointPressure(point) });
        canvas.requestPaint();
    }

    function endStroke() {
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

    function cancelStroke() {
        root.drawing = false;
        root.erasing = false;
        root.eraseDirty = false;
        root.current = [];
        canvas.requestPaint();
    }

    function hasPressure(points) {
        if (!points || points.length === 0) return false;
        for (var i = 0; i < points.length; i++) {
            if (points[i].p === undefined || points[i].p === null) return false;
        }
        return true;
    }

    function pressureWidth(base, p) {
        return base * (0.25 + 0.75 * Math.max(0, Math.min(1, p)));
    }

    // Legacy strokes and mouse/touch input have no pressure samples, so they
    // keep the original uniform path rendering.
    function paintStroke(ctx, stroke) {
        var points = stroke && stroke.points ? stroke.points : [];
        if (points.length < 2) return;
        var base = stroke.width || root.penWidth;
        ctx.strokeStyle = stroke.color || root.penColor;
        if (root.pressureEnabled && root.hasPressure(points)) {
            for (var i = 1; i < points.length; i++) {
                var a = points[i - 1];
                var b = points[i];
                ctx.lineWidth = root.pressureWidth(base, ((a.p || 0) + (b.p || 0)) / 2);
                ctx.beginPath();
                ctx.moveTo(a.x, a.y);
                ctx.lineTo(b.x, b.y);
                ctx.stroke();
            }
            return;
        }
        ctx.lineWidth = base;
        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        for (var j = 1; j < points.length; j++) ctx.lineTo(points[j].x, points[j].y);
        ctx.stroke();
    }

    onStrokesChanged: canvas.requestPaint()

    Column {
        anchors.fill: parent
        spacing: root.th.spaceCompact
        Item {
            id: toolbar
            width: parent.width
            height: Math.max(22, root.th.iconBody)

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
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
            }

            // Copy exposes the drawing as SVG markup or as the raw stroke
            // list, so it can be reused in other tools.
            Item {
                id: copyButton
                objectName: "copyWhiteboard"
                width: 22
                height: 22
                anchors.right: clearButton.left
                anchors.rightMargin: root.th.space1
                anchors.verticalCenter: parent.verticalCenter
                Accessible.role: Accessible.Button
                Accessible.name: "Copy whiteboard"

                Rectangle {
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: copyHover.hovered ? root.th.hover : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: "copy"
                    size: root.th.iconBody
                    color: root.th.muted
                }
                HoverHandler { id: copyHover }
                TapHandler {
                    onTapped: {
                        var p = copyButton.mapToItem(null, copyButton.width + 4, copyButton.height + 6);
                        copyMenu.openAt(p.x, p.y);
                    }
                }
            }

            // Clear is kept at the far right, away from the drawing tools.
            Icon {
                id: clearButton
                objectName: "clearStrokes"
                name: "trash-2"
                size: root.th.iconBody
                width: 22
                height: 22
                color: root.th.muted
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                TapHandler {
                    onTapped: {
                        var p = clearButton.mapToItem(null, clearButton.width + 4, clearButton.height + 6);
                        clearMenu.openAt(p.x, p.y);
                    }
                }
            }
        }

        Canvas {
            id: canvas
            objectName: "whiteboardCanvas"
            width: parent.width
            height: parent.height - toolbar.height - root.th.spaceCompact
            renderStrategy: Canvas.Cooperative
            // Resizing the card grows or shrinks the drawing area. Repainting
            // at the new size keeps strokes at their original coordinates
            // instead of letting Qt scale the old raster buffer.
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                for (var i = 0; i < root.strokes.length; i++)
                    root.paintStroke(ctx, root.strokes[i]);
                if (root.current.length > 1)
                    root.paintStroke(ctx, { color: root.penColor, width: root.penWidth, points: root.current });
            }

            HoverHandler {
                id: hoverHandler
                cursorShape: root.cursorInside ? Qt.BlankCursor : Qt.ArrowCursor
                onPointChanged: if (!drawHandler.active) root.updateCursor(point)
                onHoveredChanged: if (hovered) root.updateCursor(point)
            }

            PointHandler {
                id: drawHandler
                acceptedButtons: Qt.LeftButton
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onActiveChanged: {
                    if (active) root.beginStroke(point);
                    else root.endStroke();
                }
                onPointChanged: if (active) root.extendStroke(point)
                onCanceled: root.cancelStroke()
            }

            // Pencil cursor: a dot matching the current stroke size.
            Rectangle {
                objectName: "pencilCursor"
                visible: root.cursorInside && root.tool === "draw"
                width: Math.max(1, root.penWidth)
                height: width
                radius: width / 2
                color: root.penColor
                antialiasing: true
                x: root.cursorPos.x - width / 2
                y: root.cursorPos.y - height / 2
            }

            // Eraser cursor: an empty circle matching the eraser size.
            Rectangle {
                objectName: "eraserCursor"
                visible: root.cursorInside && root.tool === "erase"
                width: Math.max(4, root.eraserRadius * 2)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: root.th.text
                opacity: 0.9
                antialiasing: true
                x: root.cursorPos.x - width / 2
                y: root.cursorPos.y - height / 2
            }
        }
    }

    ContextMenu {
        id: copyMenu
        parent: root.Window.window ? root.Window.window.contentItem : null
        th: root.th
        actions: [
            { label: "Copy as SVG", icon: "code", action: "svg" },
            { label: "Copy as Stroke", icon: "pencil", action: "stroke" }
        ]
        onTriggered: function (action) {
            if (!root.app || !root.card) return;
            if (action === "svg")
                root.app.copyWhiteboardSvg(root.card.id, canvas.width, canvas.height);
            else if (action === "stroke")
                root.app.copyWhiteboardStrokes(root.card.id);
        }
    }

    ContextMenu {
        id: clearMenu
        objectName: "whiteboardClearMenu"
        parent: root.Window.window ? root.Window.window.contentItem : null
        width: 260
        th: root.th
        actions: [
            {
                label: "Delete whiteboard content",
                icon: "trash-2",
                action: "clear",
                danger: true,
                dangerFill: true
            }
        ]
        onTriggered: function (action) {
            if (action === "clear") root.clearContent();
        }
    }
}
