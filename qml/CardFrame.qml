import QtQuick

FocusScope {
    id: root

    property var app
    property var th
    property var card
    readonly property var settings: {
        try { return JSON.parse(root.app.settingsJson); } catch (e) { return ({}); }
    }
    property string gridId: ""
    property bool selected: false
    property bool resizable: true
    property bool showChrome: true
    default property alias bodyData: body.data

    signal selectRequested(bool additive)
    signal movedBy(real dx, real dy)
    Accessible.role: Accessible.Grouping
    Accessible.name: (root.card ? (root.card.title || root.card.type) : "Card") + " card"
    signal menuRequested(var card, real globalX, real globalY)
    signal dateLinkRequested(string sourceCardId, string sourceItemId, string linkId, string defaultDate)
    signal calendarManagerRequested()
    property bool cardHovered: false
    property bool menuHovered: false
    property bool resizeHovered: false
    property real parallaxX: 0
    property real parallaxY: 0

    x: card ? card.x : 0
    y: card ? card.y : 0
    width: card ? card.width : 320
    height: card ? card.height : 240
    z: selected ? 20 : (root.cardHovered ? 10 : 1)
    property bool entered: false
    property bool editingTitle: false
    readonly property real minimumWidth: {
        var t = root.card ? root.card.type : "";
        if (t === "calendar") return 420;
        if (t === "kanban" || t === "git") return 360;
        if (t === "website" || t === "ai" || t === "whiteboard") return 320;
        if (t === "file" || t === "checklist") return 300;
        return 240;
    }
    readonly property real minimumHeight: {
        var t = root.card ? root.card.type : "";
        if (t === "calendar") return 500;
        if (t === "git" || t === "kanban") return 260;
        if (t === "website" || t === "whiteboard") return 220;
        if (t === "ai") return 300;
        return 180;
    }

    function enter() {
        if (entered) return;
        entered = true;
        if (root.settings && root.settings.spawn_animations && !root.settings.reduced_motion) {
            opacity = 0;
            enterAnim.start();
        }
    }

    onSettingsChanged: enter()

    function updateParallax(px, py) {
        if (!root.settings || !root.settings.card_parallax || root.settings.reduced_motion) {
            parallaxX = 0;
            parallaxY = 0;
            return;
        }
        parallaxX = (px / Math.max(1, width) - 0.5) * -8;
        parallaxY = (py / Math.max(1, height) - 0.5) * -8;
    }

    onCardChanged: {
        root.editingTitle = false;
        if (!mover.active && !resizer.active) {
            x = card.x;
            y = card.y;
            width = card.width;
            height = card.height;
        }
        if (!titleInput.activeFocus) titleInput.text = card.title || "";
    }
    Component.onCompleted: enter()

    NumberAnimation {
        id: enterAnim
        target: root
        property: "opacity"
        to: 1
        duration: root.th.motionSlow
        easing.type: Easing.OutCubic
    }

    function commit(payloadPatch, textValue) {
        var payload = {};
        if (payloadPatch) {
            for (var k in payloadPatch) payload[k] = payloadPatch[k];
        }
        app.updateCard(JSON.stringify({
            id: card.id,
            x: root.x,
            y: root.y,
            width: root.width,
            height: root.height,
            title: titleInput.text,
            text: textValue !== undefined && textValue !== null ? textValue : root.card.text,
            payload: payload
        }));
    }

    function snapValue(value) {
        return (root.settings && root.settings.grid_magnetic) ? Math.round(value / 32) * 32 : value;
    }

    function commitGeometry() {
        if (root.settings && root.settings.grid_magnetic) {
            root.x = snapValue(root.x);
            root.y = snapValue(root.y);
        }
        root.width = Math.max(root.minimumWidth, root.settings && root.settings.grid_magnetic ? snapValue(root.width) : root.width);
        root.height = Math.max(root.minimumHeight, root.settings && root.settings.grid_magnetic ? snapValue(root.height) : root.height);
        app.updateCard(JSON.stringify({
            id: card.id,
            x: root.x,
            y: root.y,
            width: root.width,
            height: root.height
        }));
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Math.max(0, Math.min(28, root.settings && root.settings.card_radius !== undefined ? root.settings.card_radius : root.th.radiusCard))
        transform: Translate { x: root.parallaxX; y: root.parallaxY }
        color: root.th.card
        border.width: root.selected ? root.th.borderWidthStrong : root.th.borderWidth
        border.color: root.selected ? root.th.accent : (root.cardHovered ? root.th.borderStrong : root.th.border)
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    Item {
        visible: root.selected
        width: 6
        height: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -3
        z: 2

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 6
            height: 6
            radius: root.th.radiusSmall
            color: root.card.color || root.th.accent
            border.width: root.th.borderWidth
            border.color: root.th.accent
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 6
            width: 1
            height: 4
            color: root.th.accent
            opacity: root.th.opacityEmphasis
        }
    }

    Item {
        id: header
        visible: root.showChrome
        transform: Translate { x: root.parallaxX; y: root.parallaxY }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.th ? root.th.cardHeaderHeight : 44

        Row {
            anchors.left: parent.left
            anchors.leftMargin: root.th.space4
            anchors.right: menuButton.left
            anchors.rightMargin: root.th.space2
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.th.space2
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.card.icon || "square"
                size: root.th.iconBody
                color: root.th.text2
            }

            Text {
                id: titleLabel
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.editingTitle
                text: root.card.title || "Untitled"
                color: root.card.title ? root.th.text : root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                font.weight: root.th.fontWeightMedium
                elide: Text.ElideRight
            }

            TextInput {
                id: titleInput
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                visible: root.editingTitle
                text: root.card.title || ""
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                font.weight: root.th.fontWeightMedium
                selectByMouse: true
                selectionColor: root.th.accent
                clip: true
                onEditingFinished: {
                    root.commit(null);
                    root.editingTitle = false;
                }
                Keys.onEscapePressed: {
                    text = root.card.title || "";
                    root.editingTitle = false;
                    focus = false;
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            // Let the DragHandler take over once the pointer moves, otherwise
            // the mouse area keeps the grab and the card cannot be moved.
            preventStealing: false
            onClicked: function (mouse) {
                mouse.accepted = true;
                root.selectRequested(!!(mouse.modifiers & Qt.ControlModifier));
            }
            onDoubleClicked: function (mouse) {
                mouse.accepted = true;
                root.editingTitle = true;
                Qt.callLater(function () {
                    titleInput.forceActiveFocus();
                    titleInput.selectAll();
                });
            }
        }

        Icon {
            visible: root.card && !!root.card.syncId
            anchors.right: menuButton.left
            anchors.rightMargin: root.card && root.card.locked ? 26 : 6
            anchors.verticalCenter: parent.verticalCenter
            name: "link"
            size: root.th.iconSmall
            color: root.th.accent
        }

        Icon {
            visible: root.card && root.card.locked
            anchors.right: menuButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            name: "pin"
            size: root.th.iconSmall
            color: root.th.accent
        }

        Item {
            id: menuButton
            width: 32
            height: 32
            anchors.right: parent.right
            anchors.rightMargin: root.th.space3
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.cardHovered || root.selected ? 1 : 0

            Rectangle {
                anchors.fill: parent
                radius: root.th.radiusControl
                color: root.menuHovered ? root.th.hover : "transparent"
            }
            Icon {
                anchors.centerIn: parent
                name: "ellipsis"
                size: root.th.iconBody
                color: root.th.text2
            }
            HoverHandler { id: menuHover
                onHoveredChanged: root.menuHovered = hovered
            }
            TapHandler {
                onTapped: {
                    var p = root.mapToItem(null, root.width - 20, 28);
                    root.menuRequested(root.card, p.x, p.y);
                }
            }
        }

        DragHandler {
            id: mover
            target: null
            enabled: !root.card.locked && !root.editingTitle
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            cursorShape: Qt.SizeAllCursor
            property real lastX: 0
            property real lastY: 0
            property real totalX: 0
            property real totalY: 0
            onActiveChanged: {
                if (active) {
                    lastX = 0;
                    lastY = 0;
                    totalX = 0;
                    totalY = 0;
                    if (!root.selected) root.selectRequested(false);
                } else {
                    root.commitGeometry();
                    if (Math.abs(totalX) > 0.5 || Math.abs(totalY) > 0.5)
                        root.movedBy(totalX, totalY);
                }
            }
            onTranslationChanged: {
                var z = Math.max(0.2, root.app.zoom);
                var dx = (translation.x - lastX) / z;
                var dy = (translation.y - lastY) / z;
                root.x += dx;
                root.y += dy;
                totalX += dx;
                totalY += dy;
                lastX = translation.x;
                lastY = translation.y;
            }
        }


    }

    Item {
        id: body
        transform: Translate { x: root.parallaxX; y: root.parallaxY }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.showChrome ? header.bottom : parent.top
        anchors.bottom: parent.bottom
        anchors.margins: root.showChrome ? 16 : 12
        anchors.topMargin: root.showChrome ? 0 : 12
        clip: true
    }

    Item {
        id: resizeHandle
        visible: root.resizable && !root.card.locked
        width: 18
        height: 18
        z: 10
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 8
        anchors.bottomMargin: 8
        opacity: root.resizeHovered || root.selected ? 1 : 0

        Icon {
            anchors.centerIn: parent
            name: "maximize-2"
            size: root.th.iconSmall - 2
            color: root.th.muted
            rotation: 90
        }

        Rectangle {
            id: resizeTip
            anchors.right: parent.right
            anchors.bottom: parent.top
            anchors.bottomMargin: 6
            width: resizeTipText.implicitWidth + 16
            height: 24
            radius: root.th.radiusKeycap
            color: root.th.menu
            border.width: 1
            border.color: root.th.border
            visible: resizeHover.hovered
            Text {
                id: resizeTipText
                anchors.centerIn: parent
                text: "Ctrl + right-click to resize"
                color: root.th.text2
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }

        HoverHandler { id: resizeHover
            onHoveredChanged: root.resizeHovered = hovered
        }
        DragHandler {
            id: resizer
            target: null
            cursorShape: Qt.SizeFDiagCursor
            property real lastX: 0
            property real lastY: 0
            onActiveChanged: {
                if (active) {
                    lastX = 0;
                    lastY = 0;
                    root.selectRequested(false);
                } else {
                    root.commitGeometry();
                }
            }
            onTranslationChanged: {
                var z = Math.max(0.2, root.app.zoom);
                root.width = Math.max(root.minimumWidth, root.width + (translation.x - lastX) / z);
                root.height = Math.max(root.minimumHeight, root.height + (translation.y - lastY) / z);
                lastX = translation.x;
                lastY = translation.y;
            }
        }
    }

    HoverHandler { id: hover
        onHoveredChanged: {
            root.cardHovered = hovered;
            if (!hovered) {
                root.parallaxX = 0;
                root.parallaxY = 0;
            }
        }
        onPointChanged: root.updateParallax(point.position.x, point.position.y)
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: function (point, button) {
            root.selectRequested(!!(point.modifiers & Qt.ControlModifier));
        }
    }

    MouseArea {
        id: rightButton
        anchors.fill: parent
        z: 9
        acceptedButtons: Qt.RightButton
        property bool resizing: false
        property bool menuPending: false
        property real startW: 0
        property real startH: 0
        property real startX: 0
        property real startY: 0

        onPressed: function (mouse) {
            if (!root.card) return;
            if (root.card.locked) {
                menuPending = true;
                mouse.accepted = true;
                return;
            }
            if (mouse.modifiers & Qt.ControlModifier) {
                resizing = true;
                menuPending = false;
                startW = root.width;
                startH = root.height;
                startX = mouse.x;
                startY = mouse.y;
                root.selectRequested(false);
                mouse.accepted = true;
            } else {
                resizing = false;
                menuPending = true;
                mouse.accepted = true;
            }
        }
        onPositionChanged: function (mouse) {
            if (!resizing) return;
            var z = Math.max(0.2, root.app ? root.app.zoom : 1);
            root.width = Math.max(root.minimumWidth, startW + (mouse.x - startX) / z);
            root.height = Math.max(root.minimumHeight, startH + (mouse.y - startY) / z);
        }
        onReleased: function (mouse) {
            if (resizing) {
                resizing = false;
                root.commitGeometry();
                mouse.accepted = true;
            } else if (menuPending) {
                menuPending = false;
                var p = root.mapToItem(null, root.width - 20, 28);
                root.menuRequested(root.card, p.x, p.y);
                mouse.accepted = true;
            }
        }
        onCanceled: {
            resizing = false;
            menuPending = false;
        }
    }
}
