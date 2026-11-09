import QtQuick
import QtQuick.Controls
import QtQuick.Window

// A live copy of a canvas card in its own top-level window.
//
// The window is frameless so it behaves like a picture-in-picture surface.
// Dragging the title bar asks the compositor for a system move, which is what
// Wayland requires; the manual fallback keeps X11 and test platforms usable.
Window {
    id: win

    property var app
    property var th
    property string cardId: ""
    property var cardData: null
    property string bodySource: ""
    property string gridId: ""
    property var webProfile: null
    property bool pinned: true

    property real initialWidth: 360
    property real initialHeight: 420

    signal cardReturned()
    signal dateLinkRequested(string sourceCardId, string sourceItemId, string linkId, string defaultDate)
    signal calendarManagerRequested()

    visible: true
    color: win.th ? win.th.bg : "#111111"
    flags: Qt.Window | Qt.FramelessWindowHint
           | (win.pinned ? Qt.WindowStaysOnTopHint : 0)
    // Leave the picture-in-picture marker in the title so window rules can
    // match it (the Wayland app_id is shared by the whole process).
    title: "Picture-in-Picture — " + (win.cardData
        ? (win.cardData.title || win.cardData.type || "Card") : "Card")

    width: win.initialWidth
    height: win.initialHeight
    minimumWidth: 280
    minimumHeight: titleBar.height + 200

    readonly property int titleBarHeight: 38

    function returnToCanvas() {
        win.cardReturned();
        win.close();
    }

    onClosing: win.cardReturned()
    onPinnedChanged: {
        // Some platforms recreate the native window when the flags change.
        if (!win.visible) win.visible = true;
    }

    Rectangle {
        anchors.fill: parent
        color: win.th ? win.th.bg : "#111111"
        border.width: win.th ? win.th.borderWidth : 1
        border.color: win.th ? win.th.borderStrong : "#444444"
    }

    Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: win.titleBarHeight
        color: win.th ? win.th.card : "#222222"
        radius: win.th ? win.th.radiusCard : 8

        // Square off the bottom corners so it joins the card area below.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius
            color: parent.color
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: win.th ? win.th.borderWidth : 1
            color: win.th ? win.th.border : "#333333"
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: win.th ? win.th.space3 : 12
            anchors.right: titleButtons.left
            anchors.rightMargin: win.th ? win.th.space2 : 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: win.th ? win.th.space2 : 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: win.cardData ? (win.cardData.icon || "app-window") : "app-window"
                size: win.th ? win.th.iconSmall : 14
                color: win.th ? win.th.text2 : "#bbbbbb"
            }

            Text {
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                text: win.cardData ? (win.cardData.title || win.cardData.type || "Card") : "Card"
                color: win.th ? win.th.text : "#eeeeee"
                font.family: win.th ? win.th.fontFamily : "sans"
                font.pixelSize: win.th ? win.th.fontSizeSmall : 12
                font.weight: win.th ? win.th.fontWeightMedium : 500
                elide: Text.ElideRight
            }
        }

        Row {
            id: titleButtons
            anchors.right: parent.right
            anchors.rightMargin: win.th ? win.th.space2 : 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Item {
                id: pinButton
                width: 26
                height: 26
                Accessible.role: Accessible.Button
                Accessible.name: win.pinned ? "Unpin picture-in-picture window" : "Keep picture-in-picture window on top"

                Rectangle {
                    anchors.fill: parent
                    radius: win.th ? win.th.radiusControl : 4
                    color: pinHover.hovered ? (win.th ? win.th.hover : "#333333") : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: win.pinned ? "pin" : "pin-off"
                    size: win.th ? win.th.iconBody : 16
                    color: win.pinned ? (win.th ? win.th.accent : "#d98e5c")
                                       : (win.th ? win.th.text2 : "#bbbbbb")
                }
                HoverHandler { id: pinHover }
                TapHandler { onTapped: win.pinned = !win.pinned }
                ToolTip.visible: pinHover.hovered
                ToolTip.delay: 500
                ToolTip.text: win.pinned ? "Stop keeping this card on top"
                                         : "Keep this card on top"
            }

            Item {
                id: returnButton
                width: 26
                height: 26
                Accessible.role: Accessible.Button
                Accessible.name: "Back card to canvas"

                Rectangle {
                    anchors.fill: parent
                    radius: win.th ? win.th.radiusControl : 4
                    color: returnHover.hovered ? (win.th ? win.th.hover : "#333333") : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: "undo-2"
                    size: win.th ? win.th.iconBody : 16
                    color: win.th ? win.th.text2 : "#bbbbbb"
                }
                HoverHandler { id: returnHover }
                TapHandler { onTapped: win.returnToCanvas() }
                ToolTip.visible: returnHover.hovered
                ToolTip.delay: 500
                ToolTip.text: "Back card to canvas"
            }
        }

        DragHandler {
            id: titleMover
            target: null
            cursorShape: Qt.SizeAllCursor
            property real lastX: 0
            property real lastY: 0
            property bool systemMove: false

            onActiveChanged: {
                if (active) {
                    systemMove = win.startSystemMove();
                    lastX = 0;
                    lastY = 0;
                } else {
                    systemMove = false;
                }
            }
            onTranslationChanged: {
                if (!active || systemMove) return;
                win.x += translation.x - lastX;
                win.y += translation.y - lastY;
                lastX = translation.x;
                lastY = translation.y;
            }
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        anchors.bottom: parent.bottom
        clip: true

        Loader {
            id: bodyLoader
            anchors.fill: parent
            source: win.bodySource
            asynchronous: false

            onLoaded: {
                // Set the detached flag first: assigning card below triggers
                // CardFrame.onCardChanged, which must not copy the canvas
                // geometry over the window-filling layout.
                item.detached = true;
                item.showChrome = false;
                item.app = Qt.binding(function () { return win.app; });
                item.th = Qt.binding(function () { return win.th; });
                item.gridId = Qt.binding(function () { return win.gridId; });
                if (win.cardData && win.cardData.type === "website")
                    item.webProfile = Qt.binding(function () { return win.webProfile; });

                item.card = Qt.binding(function () { return win.cardData; });

                item.dateLinkRequested.connect(function (sourceCardId, sourceItemId, linkId, defaultDate) {
                    win.dateLinkRequested(sourceCardId, sourceItemId, linkId, defaultDate);
                });
                item.calendarManagerRequested.connect(function () {
                    win.calendarManagerRequested();
                });
            }
        }
    }

    Item {
        width: 18
        height: 18
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 100

        Icon {
            anchors.centerIn: parent
            name: "maximize-2"
            size: win.th ? win.th.iconSmall - 2 : 12
            color: win.th ? win.th.muted : "#888888"
            rotation: 90
            opacity: resizeHover.hovered ? 1 : 0
        }

        HoverHandler { id: resizeHover }
        DragHandler {
            id: resizeMover
            target: null
            cursorShape: Qt.SizeFDiagCursor
            onActiveChanged: if (active)
                win.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }
}
