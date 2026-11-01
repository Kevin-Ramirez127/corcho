import QtQuick

Item {
    id: root

    property var app
    property var th
    property var settings
    property var cards: []
    property string selectedId: ""

    signal menuRequested(var card, real globalX, real globalY)
    signal backgroundMenuRequested(real globalX, real globalY, real worldX, real worldY)
    signal createRequested(real worldX, real worldY)

    clip: true
    property bool panning: false
    property bool syncingModel: false

    ListModel { id: cardModel }

    function syncCards() {
        syncingModel = true;
        var arr = root.cards || [];
        // remove deleted
        for (var i = cardModel.count - 1; i >= 0; i--) {
            var existing = cardModel.get(i).card;
            var keep = false;
            for (var j = 0; j < arr.length; j++) {
                if (arr[j].id === existing.id) { keep = true; break; }
            }
            if (!keep) cardModel.remove(i);
        }
        // update and insert in order
        for (var k = 0; k < arr.length; k++) {
            var card = arr[k];
            var found = -1;
            for (var m = 0; m < cardModel.count; m++) {
                if (cardModel.get(m).card.id === card.id) { found = m; break; }
            }
            if (found < 0) {
                cardModel.insert(Math.min(k, cardModel.count), { "card": card });
            } else {
                if (found !== k) cardModel.move(found, k, 1);
                cardModel.setProperty(k, "card", card);
            }
        }
        syncingModel = false;
    }

    onCardsChanged: syncCards()
    Component.onCompleted: syncCards()
    property bool minimapVisible: false

    function bodyFor(type) {
        switch (type) {
        case "note": return "CardBodyNote.qml";
        case "website": return "CardBodyWebsite.qml";
        case "bookmark": return "CardBodyBookmark.qml";
        case "api": return "CardBodyApi.qml";
        case "ai": return "CardBodyAi.qml";
        case "script": return "CardBodyScript.qml";
        case "fragment": return "CardBodyFragment.qml";
        case "gridlink": return "CardBodyGridLink.qml";
        case "checklist": return "CardBodyChecklist.qml";
        case "kanban": return "CardBodyKanban.qml";
        case "whiteboard": return "CardBodyWhiteboard.qml";
        case "pomodoro": return "CardBodyPomodoro.qml";
        case "mpris": return "CardBodyMpris.qml";
        default: return "CardBodyNote.qml";
        }
    }

    function inView(card) {
        var z = Math.max(0.2, app.zoom);
        var left = -app.panX / z;
        var top = -app.panY / z;
        var right = left + width / z;
        var bottom = top + height / z;
        var m = 320;
        return card.x + card.width > left - m && card.x < right + m && card.y + card.height > top - m && card.y < bottom + m;
    }

    function zoomAt(factor, sx, sy) {
        var oldZoom = Math.max(0.2, app.zoom);
        var next = Math.min(3.0, Math.max(0.2, oldZoom * factor));
        var wx = (sx - app.panX) / oldZoom;
        var wy = (sy - app.panY) / oldZoom;
        app.setView(sx - wx * next, sy - wy * next, next);
    }

    function centerAt(wx, wy) {
        app.setView(width / 2 - wx * app.zoom, height / 2 - wy * app.zoom, app.zoom);
        app.saveNow();
    }

    Rectangle {
        anchors.fill: parent
        color: root.th.bg
    }

    Canvas {
        id: gridDots
        anchors.fill: parent
        property real px: root.app.panX
        property real py: root.app.panY
        property real pz: root.app.zoom
        onPxChanged: requestPaint()
        onPyChanged: requestPaint()
        onPzChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var z = Math.max(0.2, root.app.zoom);
            var step = 32 * z;
            if (step < 9) step *= 2;
            var ox = ((root.app.panX % step) + step) % step;
            var oy = ((root.app.panY % step) + step) % step;
            var opacity = root.settings && root.settings.grid_opacity !== undefined ? root.settings.grid_opacity : 0.6;
            ctx.fillStyle = Qt.rgba(root.th.text.r, root.th.text.g, root.th.text.b, 0.09 * (opacity / 0.6));
            for (var x = ox; x < width; x += step) {
                for (var y = oy; y < height; y += step) {
                    ctx.beginPath();
                    ctx.arc(x, y, 1.1, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }

    MouseArea {
        id: background
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton | Qt.BackButton
        property point lastPoint
        property bool panning: false

        onPressed: function (mouse) {
            lastPoint = Qt.point(mouse.x, mouse.y);
            panning = mouse.button === Qt.MiddleButton || mouse.button === Qt.LeftButton;
            root.panning = panning;
            root.selectedId = "";
        }
        onPositionChanged: function (mouse) {
            if (!panning) return;
            var dx = mouse.x - lastPoint.x;
            var dy = mouse.y - lastPoint.y;
            lastPoint = Qt.point(mouse.x, mouse.y);
            root.app.setView(root.app.panX + dx, root.app.panY + dy, root.app.zoom);
        }
        onReleased: {
            if (panning) root.app.saveNow();
            panning = false;
            root.panning = false;
            if (root.settings && root.settings.minimap_display === "panning") {
                minimapHideTimer.restart();
            }
        }
        onClicked: function (mouse) {
            if (mouse.button === Qt.LeftButton && root.settings && root.settings.grid_ripple && !root.settings.reduced_motion) {
                ripple.x = mouse.x - 24;
                ripple.y = mouse.y - 24;
                rippleAnim.restart();
            }
            if (mouse.button === Qt.RightButton) {
                var g = root.mapToItem(null, mouse.x, mouse.y);
                var z = Math.max(0.2, root.app.zoom);
                root.backgroundMenuRequested(g.x, g.y, (mouse.x - root.app.panX) / z, (mouse.y - root.app.panY) / z);
            }
        }
        onDoubleClicked: function (mouse) {
            var z = Math.max(0.2, root.app.zoom);
            root.createRequested((mouse.x - root.app.panX) / z, (mouse.y - root.app.panY) / z);
        }
        onWheel: function (wheel) {
            var wantPan = !root.settings || root.settings.trackpad_pan !== false;
            if (wheel.modifiers & Qt.ControlModifier || !wantPan) {
                root.zoomAt(wheel.angleDelta.y > 0 ? 1.12 : 0.89, wheel.x, wheel.y);
            } else {
                root.app.setView(root.app.panX - wheel.angleDelta.x * 0.7, root.app.panY - wheel.angleDelta.y * 0.7, root.app.zoom);
            }
        }
    }

    Item {
        id: world
        x: root.app.panX
        y: root.app.panY
        scale: root.app.zoom
        transformOrigin: Item.TopLeft

        Repeater {
            model: cardModel

            delegate: Loader {
                id: cardLoader
                required property var card

                active: root.inView(card)
                source: root.bodyFor(card.type)
                asynchronous: false

                onCardChanged: if (item) item.card = card

                onLoaded: {
                    item.card = card;
                    item.app = root.app;
                    item.th = root.th;
                    item.settings = root.settings;
                    item.gridId = root.app.activeGridId;
                    item.selected = Qt.binding(function () { return root.selectedId === cardLoader.card.id; });
                    item.selectRequested.connect(function () { root.selectedId = cardLoader.card.id; });
                    item.menuRequested.connect(function (cardData, gx, gy) {
                        root.selectedId = cardData.id;
                        root.menuRequested(cardData, gx, gy);
                    });
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: root.cards.length === 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "This grid is empty"
            color: root.th.text
            font.family: root.th.fontFamily
            font.pixelSize: 18
            font.weight: 500
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Double-click anywhere, or create your first card"
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: 13
        }
        AppButton {
            anchors.horizontalCenter: parent.horizontalCenter
            th: root.th
            icon: "plus"
            text: "Create card"
            variant: "solid"
            onClicked: root.createRequested(-root.app.panX / root.app.zoom + root.width / 2 / root.app.zoom, -root.app.panY / root.app.zoom + root.height / 2 / root.app.zoom)
        }
    }

    Rectangle {
        id: ripple
        width: 48
        height: 48
        radius: 24
        color: "transparent"
        border.width: 1.5
        border.color: root.th.accent
        opacity: 0
        z: 2
    }

    ParallelAnimation {
        id: rippleAnim
        NumberAnimation { target: ripple; property: "width"; from: 48; to: 220; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: ripple; property: "height"; from: 48; to: 220; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: ripple; property: "x"; to: ripple.x - 86; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: ripple; property: "y"; to: ripple.y - 86; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: ripple; property: "opacity"; from: 0.55; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }

    Timer {
        id: minimapHideTimer
        interval: 900
        onTriggered: root.minimapVisible = false
    }

    Minimap {
        visible: root.settings && root.settings.minimap_display !== "hidden"
                 && (root.settings.minimap_display !== "panning" || root.panning || root.minimapVisible)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        app: root.app
        th: root.th
        cards: root.cards
        viewportWidth: root.width
        viewportHeight: root.height
        minimapWidth: root.settings && root.settings.minimapSize === "small" ? 132 : (root.settings && root.settings.minimapSize === "large" ? 240 : 176)
        minimapHeight: root.settings && root.settings.minimapSize === "small" ? 84 : (root.settings && root.settings.minimapSize === "large" ? 152 : 112)
        onCenterAt: function (wx, wy) { root.centerAt(wx, wy); }
    }
}
