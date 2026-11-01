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
    property bool cardHovered: false
    property bool menuHovered: false
    property bool resizeHovered: false

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
            scale = 0.97;
            enterAnim.start();
        }
    }

    onSettingsChanged: enter()

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
        properties: "opacity,scale"
        to: 1
        duration: 130
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
        app.saveNow();
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 14
        color: root.th.card
        border.width: root.selected ? 1.5 : 1
        border.color: root.selected ? root.th.accent : (root.cardHovered ? root.th.borderStrong : root.th.border)
        Behavior on border.color { ColorAnimation { duration: 110 } }

        Rectangle {
            width: 20
            height: 3
            radius: 2
            x: 14
            y: 0
            anchors.topMargin: -1
            color: root.card.color || root.th.accent
            opacity: 0.85
        }
    }

    Item {
        id: header
        visible: root.showChrome
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: menuButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.card.icon || "square"
                size: 15
                color: root.card.color || root.th.text2
            }

            TextInput {
                id: titleInput
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                text: root.card.title || ""
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: 13
                font.weight: 500
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
            width: 28
            height: 28
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.cardHovered || root.selected ? 1 : 0

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: root.menuHovered ? root.th.hover : "transparent"
            }
            Icon {
                anchors.centerIn: parent
                name: "ellipsis"
                size: 15
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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.showChrome ? header.bottom : parent.top
        anchors.bottom: parent.bottom
        anchors.margins: root.showChrome ? 14 : 10
        anchors.topMargin: root.showChrome ? 0 : 10
        clip: true
    }

    Item {
        id: resizeHandle
        visible: root.resizable && !root.card.locked
        width: 18
        height: 18
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        opacity: root.resizeHovered || root.selected ? 1 : 0

        Icon {
            anchors.centerIn: parent
            name: "maximize-2"
            size: 11
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
        onHoveredChanged: root.cardHovered = hovered
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.selectRequested()
    }
}
