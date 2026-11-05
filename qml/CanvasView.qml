import QtQuick

Item {
    id: root

    property var app
    property var th
    property var settings
    property var cards: []
    property string selectedId: ""
    property var selectedIds: []
    property string activeAiId: ""
    property real linkPhase: 0

    function activateAi(id) {
        root.activeAiId = id;
        root.linkPhase = 0;
        aiPulseStop.restart();
    }

    Timer {
        interval: 33
        repeat: true
        running: root.activeAiId !== ""
        onTriggered: root.linkPhase += 0.035
    }

    Timer {
        id: aiPulseStop
        interval: 4500
        onTriggered: root.activeAiId = ""
    }
    property bool marqueeActive: false
    property point marqueeStart: Qt.point(0, 0)
    property rect marqueeRect: Qt.rect(0, 0, 0, 0)

    function setSelection(ids) {
        selectedIds = ids;
        selectedId = ids.length === 1 ? ids[0] : "";
    }

    function selectCard(id, additive) {
        var list = selectedIds.slice();
        if (additive) {
            var at = list.indexOf(id);
            if (at >= 0) list.splice(at, 1); else list.push(id);
        } else {
            list = [id];
        }
        setSelection(list);
    }

    function marqueeSelection() {
        var z = Math.max(0.2, app.zoom);
        var wx = (marqueeRect.x - app.panX) / z;
        var wy = (marqueeRect.y - app.panY) / z;
        var ww = marqueeRect.width / z;
        var wh = marqueeRect.height / z;
        var ids = [];
        for (var i = 0; i < cards.length; i++) {
            var c = cards[i];
            if (c.x < wx + ww && c.x + c.width > wx && c.y < wy + wh && c.y + c.height > wy)
                ids.push(c.id);
        }
        return ids;
    }

    function cardById(id) {
        for (var i = 0; i < cards.length; i++) if (cards[i].id === id) return cards[i];
        return null;
    }

    function handleMoved(id, dx, dy) {
        var ids = [];
        var card = cardById(id);
        if (selectedIds.length > 1 && selectedIds.indexOf(id) >= 0) {
            ids = selectedIds.filter(function (value) { return value !== id; });
        } else if (card && card.group) {
            for (var i = 0; i < cards.length; i++) {
                if (cards[i].group === card.group && cards[i].id !== id) ids.push(cards[i].id);
            }
        }
        if (ids.length > 0) app.moveCards(JSON.stringify(ids), dx, dy);
    }

    readonly property var groupBounds: {
        var groups = {};
        for (var i = 0; i < cards.length; i++) {
            var c = cards[i];
            if (!c.group) continue;
            var g = groups[c.group];
            if (!g) g = groups[c.group] = { id: c.group, x: c.x, y: c.y, right: c.x + c.width, bottom: c.y + c.height };
            else {
                g.x = Math.min(g.x, c.x);
                g.y = Math.min(g.y, c.y);
                g.right = Math.max(g.right, c.x + c.width);
                g.bottom = Math.max(g.bottom, c.y + c.height);
            }
        }
        var out = [];
        for (var key in groups) {
            var b = groups[key];
            out.push({ x: b.x - 12, y: b.y - 28, width: b.right - b.x + 24, height: b.bottom - b.y + 40 });
        }
        return out;
    }

    signal menuRequested(var card, real globalX, real globalY)
    signal dateLinkRequested(string sourceCardId, string sourceItemId, string linkId, string defaultDate)
    signal calendarManagerRequested()
    signal backgroundMenuRequested(real globalX, real globalY, real worldX, real worldY)
    signal createRequested(real worldX, real worldY)

    clip: true
    property bool panning: false
    property bool syncingModel: false
    property bool modalOpen: false
    // Set by card bodies that display their own cursor over the canvas.
    property bool hidePointer: false

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
    Component.onCompleted: { syncCards(); reportViewport(); }
    onWidthChanged: viewportDebounce.restart()
    onHeightChanged: viewportDebounce.restart()
    function reportViewport() {
        if (root.app && root.width > 0 && root.height > 0)
            root.app.setViewport(root.width, root.height);
    }
    Timer {
        id: viewportDebounce
        interval: 350
        repeat: false
        onTriggered: reportViewport()
    }
    property bool minimapVisible: false

    function bodyFor(type) {
        switch (type) {
        case "note": return "CardBodyNote.qml";
        case "website": return "CardBodyWebsite.qml";
        case "bookmark": return "CardBodyBookmark.qml";
        case "api": return "CardBodyApi.qml";
        case "ai": return "CardBodyAi.qml";
        case "script": return "CardBodyScript.qml";
        case "calendar": return "CardBodyCalendar.qml";
        case "timbre": return "CardBodyTimbre.qml";
        case "portal": return "CardBodyGridPortal.qml";
        case "checklist": return "CardBodyChecklist.qml";
        case "kanban": return "CardBodyKanban.qml";
        case "whiteboard": return "CardBodyWhiteboard.qml";
        case "pomodoro": return "CardBodyPomodoro.qml";
        case "mpris": return "CardBodyMpris.qml";
        case "file": return "CardBodyFile.qml";
        case "git": return "CardBodyGit.qml";
        default: return "CardBodyNote.qml";
        }
    }

    readonly property bool hasWebsiteCards: {
        var list = cards || [];
        for (var i = 0; i < list.length; i++) if (list[i].type === "website") return true;
        return false;
    }

    readonly property var webProfile: profileHost.item ? profileHost.item.profile : null

    Loader {
        id: profileHost
        active: root.hasWebsiteCards && !(root.settings && root.settings.web_shared_profile === false)
        source: "WebProfileHost.qml"
        asynchronous: false
    }

    function inView(card) {
        var z = Math.max(0.2, app.zoom);
        var left = -app.panX / z;
        var top = -app.panY / z;
        var right = left + width / z;
        var bottom = top + height / z;
        var m = card.type === "website" ? 48 : 320;
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

    function cardAtWorld(wx, wy) {
        var cards = root.cards || [];
        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];
            if (wx >= card.x && wx <= card.x + card.width
                    && wy >= card.y && wy <= card.y + card.height)
                return card;
        }
        return null;
    }

    // Shared by right-click and the pen long-press so both open the exact
    // same creation menu at the same spot.
    function requestBackgroundMenu(px, py) {
        var g = root.mapToItem(null, px, py);
        var z = Math.max(0.2, root.app.zoom);
        root.backgroundMenuRequested(g.x, g.y,
            (px - root.app.panX) / z, (py - root.app.panY) / z);
    }

    function longPressMenuEnabled() {
        return !root.settings || root.settings.canvas_long_press_menu !== false;
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
        property color dotColor: root.th.text
        property real gridOpacity: root.settings && root.settings.grid_opacity !== undefined ? root.settings.grid_opacity : 0.6
        onPxChanged: requestPaint()
        onPyChanged: requestPaint()
        onPzChanged: requestPaint()
        onDotColorChanged: requestPaint()
        onGridOpacityChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var z = Math.max(0.2, root.app.zoom);
            var step = root.th.gridStep * z;
            if (step < 9) step *= 2;
            var ox = ((root.app.panX % step) + step) % step;
            var oy = ((root.app.panY % step) + step) % step;
            ctx.fillStyle = Qt.rgba(dotColor.r, dotColor.g, dotColor.b, root.th.gridDotOpacity * (gridOpacity / 0.6));
            for (var x = ox; x < width; x += step) {
                for (var y = oy; y < height; y += step) {
                    ctx.beginPath();
                    ctx.arc(x, y, root.th.gridDotSize, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }

    focus: true

    Keys.onPressed: function (event) {
        if (root.modalOpen) return;
        var step = (event.modifiers & Qt.ShiftModifier) ? 220 : 70;
        if (event.key === Qt.Key_Left) root.app.setView(root.app.panX + step, root.app.panY, root.app.zoom);
        else if (event.key === Qt.Key_Right) root.app.setView(root.app.panX - step, root.app.panY, root.app.zoom);
        else if (event.key === Qt.Key_Up) root.app.setView(root.app.panX, root.app.panY + step, root.app.zoom);
        else if (event.key === Qt.Key_Down) root.app.setView(root.app.panX, root.app.panY - step, root.app.zoom);
        else if (event.key === Qt.Key_Home) root.centerAt(0, 0);
        else return;
        event.accepted = true;
    }

    Canvas {
        id: linkCanvas
        anchors.fill: parent

        property real panX: root.app.panX
        property real panY: root.app.panY
        property real panZoom: root.app.zoom
        property var cardList: root.cards
        property string activeId: root.activeAiId
        property real phase: root.linkPhase

        onPanXChanged: requestPaint()
        onPanYChanged: requestPaint()
        onPanZoomChanged: requestPaint()
        onCardListChanged: requestPaint()
        onActiveIdChanged: requestPaint()
        onPhaseChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function screenX(card) { return panX + (card.x + card.width / 2) * panZoom; }
        function screenY(card) { return panY + (card.y + card.height / 2) * panZoom; }
        function edge(card, tx, ty) {
            var cx = screenX(card);
            var cy = screenY(card);
            var hw = card.width * panZoom / 2;
            var hh = card.height * panZoom / 2;
            var dx = tx - cx;
            var dy = ty - cy;
            if (dx === 0 && dy === 0) return { x: cx, y: cy };
            var sx = dx !== 0 ? hw / Math.abs(dx) : 1e9;
            var sy = dy !== 0 ? hh / Math.abs(dy) : 1e9;
            var s = Math.min(sx, sy);
            return { x: cx + dx * s, y: cy + dy * s };
        }
        function byId(id) {
            for (var i = 0; i < cardList.length; i++) if (cardList[i].id === id) return cardList[i];
            return null;
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!cardList) return;
            for (var i = 0; i < cardList.length; i++) {
                var ai = cardList[i];
                if (ai.type !== "ai" || !ai.linkedIds) continue;
                var active = ai.id === activeId;
                for (var j = 0; j < ai.linkedIds.length; j++) {
                    var src = byId(ai.linkedIds[j]);
                    if (!src) continue;
                    var ax = screenX(ai), ay = screenY(ai);
                    var sx = screenX(src), sy = screenY(src);
                    var a = edge(ai, sx, sy);
                    var b = edge(src, ax, ay);
                    var mx = (a.x + b.x) / 2;
                    var my = (a.y + b.y) / 2;
                    var dx = b.x - a.x, dy = b.y - a.y;
                    var len = Math.max(1, Math.sqrt(dx * dx + dy * dy));
                    var bend = Math.min(70, len * 0.18);
                    var cx = mx - dy / len * bend;
                    var cy = my + dx / len * bend;

                    ctx.save();
                    ctx.strokeStyle = root.th.accent;
                    ctx.globalAlpha = active ? 0.65 : 0.22;
                    ctx.lineWidth = active ? 2.4 : 1.5;
                    ctx.lineCap = "round";
                    if (active) {
                        ctx.setLineDash([7, 7]);
                        ctx.lineDashOffset = -phase * 45;
                    } else {
                        ctx.setLineDash([]);
                    }
                    ctx.beginPath();
                    ctx.moveTo(a.x, a.y);
                    ctx.quadraticCurveTo(cx, cy, b.x, b.y);
                    ctx.stroke();
                    ctx.setLineDash([]);
                    ctx.fillStyle = root.th.accent;
                    ctx.globalAlpha = active ? 0.95 : 0.45;
                    var r = active ? 3.6 : 2.4;
                    ctx.beginPath();
                    ctx.arc(a.x, a.y, r, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(b.x, b.y, r, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.restore();
                }
            }
        }
    }

    MouseArea {
        id: background
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton | Qt.BackButton
        cursorShape: panning ? Qt.ClosedHandCursor : Qt.ArrowCursor
        property point lastPoint
        property bool panning: false
        property point pressPoint: Qt.point(0, 0)
        // Kept set until the next press so the release that follows an
        // already-opened menu does not also fire the ripple/click path.
        property bool longPressFired: false

        Timer {
            id: longPressTimer
            interval: 800
            repeat: false
            onTriggered: {
                if (!background.pressed || background.panning) return;
                var z = Math.max(0.2, root.app.zoom);
                var wx = (background.pressPoint.x - root.app.panX) / z;
                var wy = (background.pressPoint.y - root.app.panY) / z;
                if (root.cardAtWorld(wx, wy)) return;
                background.longPressFired = true;
                root.requestBackgroundMenu(background.pressPoint.x, background.pressPoint.y);
            }
        }

        onPressed: function (mouse) {
            if (!root.activeFocus) root.forceActiveFocus();
            longPressTimer.stop();
            longPressFired = false;
            lastPoint = Qt.point(mouse.x, mouse.y);
            var pan = mouse.button === Qt.MiddleButton
                || (mouse.button === Qt.LeftButton && (mouse.modifiers & Qt.ShiftModifier));
            panning = pan;
            root.panning = pan;
            if (pan) return;
            if (mouse.button === Qt.LeftButton) {
                pressPoint = Qt.point(mouse.x, mouse.y);
                if (root.longPressMenuEnabled()) longPressTimer.restart();
                root.marqueeActive = true;
                root.marqueeStart = Qt.point(mouse.x, mouse.y);
                root.marqueeRect = Qt.rect(mouse.x, mouse.y, 0, 0);
                if (!(mouse.modifiers & Qt.ControlModifier)) root.setSelection([]);
            }
        }
        onPositionChanged: function (mouse) {
            if (panning) {
                var dx = mouse.x - lastPoint.x;
                var dy = mouse.y - lastPoint.y;
                lastPoint = Qt.point(mouse.x, mouse.y);
                root.app.setView(root.app.panX + dx, root.app.panY + dy, root.app.zoom);
                return;
            }
            if (longPressTimer.running) {
                var mdx = mouse.x - pressPoint.x;
                var mdy = mouse.y - pressPoint.y;
                if (mdx * mdx + mdy * mdy > 100) longPressTimer.stop();
            }
            if (!root.marqueeActive) return;
            var x0 = Math.max(0, Math.min(root.marqueeStart.x, mouse.x));
            var y0 = Math.max(0, Math.min(root.marqueeStart.y, mouse.y));
            var x1 = Math.min(width, Math.max(root.marqueeStart.x, mouse.x));
            var y1 = Math.min(height, Math.max(root.marqueeStart.y, mouse.y));
            root.marqueeRect = Qt.rect(x0, y0, x1 - x0, y1 - y0);
        }
        onReleased: {
            longPressTimer.stop();
            if (panning) root.app.saveNow();
            panning = false;
            root.panning = false;
            if (root.marqueeActive) {
                root.marqueeActive = false;
                if (root.marqueeRect.width > 4 || root.marqueeRect.height > 4)
                    root.setSelection(root.marqueeSelection());
            }
            if (root.settings && root.settings.minimap_display === "panning") {
                minimapHideTimer.restart();
            }
        }
        onCanceled: longPressTimer.stop()
        onClicked: function (mouse) {
            if (mouse.button === Qt.LeftButton && longPressFired) return;
            if (mouse.button === Qt.LeftButton && root.settings && root.settings.grid_ripple && !root.settings.reduced_motion) {
                ripple.x = mouse.x - 24;
                ripple.y = mouse.y - 24;
                rippleAnim.restart();
            }
            if (mouse.button === Qt.RightButton)
                root.requestBackgroundMenu(mouse.x, mouse.y);
        }
        onDoubleClicked: function (mouse) {
            var z = Math.max(0.2, root.app.zoom);
            var wx = (mouse.x - root.app.panX) / z;
            var wy = (mouse.y - root.app.panY) / z;
            for (var i = 0; i < root.cards.length; i++) {
                var card = root.cards[i];
                if (wx >= card.x && wx <= card.x + card.width && wy >= card.y && wy <= card.y + card.height)
                    return;
            }
            root.createRequested(wx, wy);
        }
        onWheel: function (wheel) {
            if (root.modalOpen) {
                wheel.accepted = true;
                return;
            }
            if (active) return;
            var wantPan = !(wheel.modifiers & Qt.ControlModifier)
                && (!root.settings || root.settings.trackpad_pan !== false);
            if (!wantPan) root.zoomAt(wheel.angleDelta.y > 0 ? 1.12 : 0.89, wheel.x, wheel.y);
            else root.app.setView(root.app.panX - wheel.angleDelta.x * 0.7, root.app.panY - wheel.angleDelta.y * 0.7, root.app.zoom);
        }
    }

    Item {
        id: world
        x: root.app.panX
        y: root.app.panY
        scale: root.app.zoom
        transformOrigin: Item.TopLeft

        Repeater {
            model: root.groupBounds

            delegate: Rectangle {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                radius: root.th.radiusCard + 8
                color: Qt.alpha(root.th.accent, 0.07)
                border.width: 2
                border.color: Qt.alpha(root.th.accent, 0.55)
                z: 0
            }
        }

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
                    item.app = Qt.binding(function () { return root.app; });
                    item.th = Qt.binding(function () { return root.th; });
                    item.canvasView = root;
                    item.gridId = Qt.binding(function () { return root.app.activeGridId; });
                    if (cardLoader.card.type === "website")
                        item.webProfile = Qt.binding(function () { return root.webProfile; });
                    if (cardLoader.card.type === "ai")
                        item.activated.connect(function () { root.activateAi(cardLoader.card.id); });
                    item.selected = Qt.binding(function () { return root.selectedIds.indexOf(cardLoader.card.id) >= 0; });
                    item.selectRequested.connect(function (additive) { root.selectCard(cardLoader.card.id, !!additive); });
                    item.movedBy.connect(function (dx, dy) { root.handleMoved(cardLoader.card.id, dx, dy); });
                    item.menuRequested.connect(function (cardData, gx, gy) {
                        if (root.selectedIds.indexOf(cardData.id) < 0) root.setSelection([cardData.id]);
                        root.menuRequested(cardData, gx, gy);
                    });
                    item.dateLinkRequested.connect(function (cardId, itemId, linkId, defaultDate) {
                        root.dateLinkRequested(cardId, itemId, linkId, defaultDate);
                    });
                    item.calendarManagerRequested.connect(function () {
                        root.calendarManagerRequested();
                    });
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: root.th.space3
        visible: root.cards.length === 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "This grid is empty"
            color: root.th.text
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeLarge
            font.weight: root.th.fontWeightMedium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Double-click anywhere, or create your first card"
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
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
        radius: root.th.radiusLarge
        color: "transparent"
        border.width: root.th.borderWidthStrong
        border.color: root.th.accent
        opacity: root.th.opacityNone
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

    Rectangle {
        visible: root.marqueeActive
        x: root.marqueeRect.x
        y: root.marqueeRect.y
        width: root.marqueeRect.width
        height: root.marqueeRect.height
        color: Qt.alpha(root.th.accent, 0.10)
        border.width: 1
        border.color: root.th.accent
        z: 50
    }

    MouseArea {
        anchors.fill: parent
        z: 4
        acceptedButtons: Qt.MiddleButton
        property point lastPoint
        property bool active: false
        cursorShape: root.hidePointer
            ? Qt.BlankCursor
            : (active ? Qt.ClosedHandCursor : Qt.ArrowCursor)

        onPressed: function (mouse) {
            if (!root.activeFocus) root.forceActiveFocus();
            active = true;
            root.panning = true;
            lastPoint = Qt.point(mouse.x, mouse.y);
            mouse.accepted = true;
        }
        onPositionChanged: function (mouse) {
            if (!active) return;
            var dx = mouse.x - lastPoint.x;
            var dy = mouse.y - lastPoint.y;
            lastPoint = Qt.point(mouse.x, mouse.y);
            root.app.setView(root.app.panX + dx, root.app.panY + dy, root.app.zoom);
        }
        onReleased: {
            if (!active) return;
            active = false;
            root.panning = false;
            root.app.saveNow();
        }
        onWheel: function (wheel) {
            if (root.modalOpen) {
                wheel.accepted = true;
                return;
            }
            if (active) return;
            var wantPan = !(wheel.modifiers & Qt.ControlModifier)
                && (!root.settings || root.settings.trackpad_pan !== false);
            if (!wantPan) root.zoomAt(wheel.angleDelta.y > 0 ? 1.12 : 0.89, wheel.x, wheel.y);
            else root.app.setView(root.app.panX - wheel.angleDelta.x * 0.7, root.app.panY - wheel.angleDelta.y * 0.7, root.app.zoom);
        }
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
