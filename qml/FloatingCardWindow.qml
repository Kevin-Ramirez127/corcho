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
    // The live page handed over by the canvas copy of a website card. It is
    // moved into this window instead of being loaded a second time.
    property var externalWebView: null
    property bool pinned: true
    property string floatingToken: ""
    // Opacity of the card content, in percent. The title bar stays fully
    // visible so the transparency control can always be reached again.
    property int cardOpacity: 100
    property bool opacityBarVisible: false

    readonly property real cardOpacityRatio:
        Math.max(0.03, Math.min(1.0, win.cardOpacity / 100))

    property real initialWidth: 360
    property real initialHeight: 420

    signal cardReturned()
    // Emitted with the page while the window closes, so the canvas copy can
    // take it back without ever reloading the site.
    signal webViewReturned(var view)
    signal dateLinkRequested(string sourceCardId, string sourceItemId, string linkId, string defaultDate)
    signal calendarManagerRequested()

    visible: true
    // Transparent window corners: the rounded surface below is the only
    // painted background, so nothing square shows behind its border radius.
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
           | (win.pinned ? Qt.WindowStaysOnTopHint : 0)
    // Leave the picture-in-picture marker in the title so window rules can
    // match it (the Wayland app_id is shared by the whole process). The token
    // also lets sway identify each detached window when placing them.
    title: {
        var marker = win.floatingToken ? (" #" + win.floatingToken) : "";
        return "Picture-in-Picture" + marker + " — " + (win.cardData
            ? (win.cardData.title || win.cardData.type || "Card") : "Card");
    }

    width: win.initialWidth
    height: win.initialHeight
    minimumWidth: 280
    minimumHeight: titleBar.height + 200

    readonly property int titleBarHeight: 38
    readonly property real cornerRadius: {
        try {
            var settings = JSON.parse(win.app.settingsJson);
            if (settings.card_radius !== undefined)
                return Math.max(0, Math.min(28, settings.card_radius));
        } catch (e) {}
        return win.th ? win.th.radiusCard : 8;
    }

    // Give the page back to the canvas copy before this window goes away.
    // The second call from onClosing is a no-op: the body has already
    // released the view.
    function handPageBack() {
        var item = bodyLoader.item;
        if (!item || typeof item.releaseWebView !== "function") return;
        var view = item.releaseWebView();
        if (view) win.webViewReturned(view);
    }

    function setCardOpacity(value) {
        var percent = Math.round(value);
        win.cardOpacity = Math.max(3, Math.min(100, percent));
    }

    function returnToCanvas() {
        win.handPageBack();
        win.cardReturned();
        win.close();
    }

    onClosing: {
        win.handPageBack();
        win.cardReturned();
    }
    onPinnedChanged: {
        // Some platforms recreate the native window when the flags change.
        if (!win.visible) win.visible = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: win.cornerRadius
        color: win.th ? win.th.card : "#222222"
        border.width: win.th ? win.th.borderWidth : 1
        border.color: win.th ? win.th.borderStrong : "#444444"
        opacity: win.cardOpacityRatio
    }

    Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: win.titleBarHeight
        color: "transparent"

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
                id: opacityButton
                objectName: "pipOpacityButton"
                width: 26
                height: 26
                Accessible.role: Accessible.Button
                Accessible.name: "Adjust card transparency"

                Rectangle {
                    anchors.fill: parent
                    radius: win.th ? win.th.radiusControl : 4
                    color: opacityHover.hovered || win.opacityBarVisible
                        ? (win.th ? win.th.hover : "#333333") : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: "blend"
                    size: win.th ? win.th.iconBody : 16
                    color: win.opacityBarVisible
                        ? (win.th ? win.th.accent : "#d98e5c")
                        : (win.th ? win.th.text2 : "#bbbbbb")
                }
                HoverHandler { id: opacityHover }
                TapHandler {
                    onTapped: win.opacityBarVisible = !win.opacityBarVisible
                }
                ToolTip.visible: opacityHover.hovered
                ToolTip.delay: 500
                ToolTip.text: "Card transparency"
            }

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

    // Compact slider strip shown from the transparency button. It floats
    // over the top of the card and stays fully opaque, even at 3%.
    Rectangle {
        id: opacityBar
        objectName: "pipOpacityBar"
        visible: win.opacityBarVisible
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        height: 42
        z: 50
        color: win.th ? win.th.menu : "#1c1c1c"
        border.width: win.th ? win.th.borderWidth : 1
        border.color: win.th ? win.th.border : "#333333"

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: win.th ? win.th.space3 : 12

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "blend"
                size: win.th ? win.th.iconSmall : 14
                color: win.th ? win.th.text2 : "#bbbbbb"
            }
            SliderField {
                objectName: "pipOpacitySlider"
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(80, parent.width - 108)
                th: win.th
                from: 3
                to: 100
                value: win.cardOpacity
                onMoved: win.setCardOpacity(value)
            }
            Text {
                objectName: "pipOpacityValue"
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: win.cardOpacity + "%"
                color: win.th ? win.th.text : "#eeeeee"
                font.family: win.th ? win.th.fontMono : "monospace"
                font.pixelSize: win.th ? win.th.fontSizeSmall : 12
            }
        }
    }

    Item {
        id: bodyContainer
        objectName: "pipBodyContainer"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        anchors.bottom: parent.bottom
        clip: true
        opacity: win.cardOpacityRatio

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
                item.surfaceless = true;
                item.app = Qt.binding(function () { return win.app; });
                item.th = Qt.binding(function () { return win.th; });
                item.gridId = Qt.binding(function () { return win.gridId; });
                if (win.cardData && win.cardData.type === "website")
                    item.webProfile = Qt.binding(function () { return win.webProfile; });

                // Take the live page over before the body learns its card:
                // with a URL it would otherwise open a second copy of the
                // site next to the one that was handed over.
                if (win.externalWebView && typeof item.hostWebView === "function")
                    item.hostWebView(win.externalWebView);

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
        anchors.rightMargin: 5
        anchors.bottomMargin: 5
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
