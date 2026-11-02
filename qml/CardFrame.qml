import QtQuick

FocusScope {
    id: root

    property var app
    property var th
    property var card
    property var settings
    property string gridId: ""
    property bool selected: false
    property bool resizable: true
    property bool showChrome: true
    default property alias bodyData: body.data

    signal selectRequested()
    Accessible.role: Accessible.Grouping
    Accessible.name: (root.card.title || root.card.type) + " card"
    signal menuRequested(var card, real globalX, real globalY)
    signal dateLinkRequested(string sourceCardId, string sourceItemId, string linkId, string defaultDate)
    signal calendarManagerRequested()
    property bool cardHovered: false
    property bool menuHovered: false
    property bool resizeHovered: false
    property real parallaxX: 0
    property real parallaxY: 0

    x: card.x
    y: card.y
    width: card.width
    height: card.height
    z: selected ? 20 : (root.cardHovered ? 10 : 1)
    property bool entered: false

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
            root.width = Math.max(180, snapValue(root.width));
            root.height = Math.max(120, snapValue(root.height));
        }
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
        radius: root.th.radiusCard
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
        height: root.th.cardHeaderHeight

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

            TextInput {
                id: titleInput
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                text: root.card.title || ""
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                font.weight: root.th.fontWeightMedium
                selectByMouse: true
                selectionColor: root.th.accent
                clip: true
                onEditingFinished: root.commit(null)
                Keys.onEscapePressed: {
                    text = root.card.title || "";
                    focus = false;
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: titleInput.text.length === 0
                    text: "Untitled"
                    color: root.th.muted
                    font: titleInput.font
                }
            }
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
            enabled: !root.card.locked
            cursorShape: Qt.SizeAllCursor
            property real lastX: 0
            property real lastY: 0
            onActiveChanged: {
                if (active) {
                    lastX = 0;
                    lastY = 0;
                    root.selectRequested();
                } else {
                    root.commitGeometry();
                }
            }
            onTranslationChanged: {
                var z = Math.max(0.2, root.app.zoom);
                root.x += (translation.x - lastX) / z;
                root.y += (translation.y - lastY) / z;
                lastX = translation.x;
                lastY = translation.y;
            }
        }

        TapHandler {
            onTapped: root.selectRequested()
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
        width: 20
        height: 20
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        opacity: root.resizeHovered || root.selected ? 1 : 0

        Icon {
            anchors.centerIn: parent
            name: "maximize-2"
            size: root.th.iconSmall
            color: root.th.muted
            rotation: 90
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
                    root.selectRequested();
                } else {
                    root.commitGeometry();
                }
            }
            onTranslationChanged: {
                var z = Math.max(0.2, root.app.zoom);
                root.width = Math.max(180, root.width + (translation.x - lastX) / z);
                root.height = Math.max(120, root.height + (translation.y - lastY) / z);
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
        onTapped: root.selectRequested()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            root.selectRequested();
            var p = root.mapToItem(null, root.width - 20, 28);
            root.menuRequested(root.card, p.x, p.y);
        }
    }
}
