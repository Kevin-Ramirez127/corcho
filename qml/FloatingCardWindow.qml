import QtQuick
import QtQuick.Controls
import QtQuick.Window

// A live copy of one or more canvas cards in a single top-level window.
//
// The cards are laid out in a horizontal row inside this window instead of
// being separate toplevels: Wayland does not let clients position toplevel
// windows, so a container is the only reliable way to keep them side by side.
Window {
    id: win

    property var app
    property var th
    // Array of { id, card, bodySource, width, height }. Main owns this state
    // and reassigns the array whenever card data changes.
    property var entries: []
    property string gridId: ""
    property var webProfile: null
    property bool pinned: true

    signal cardReturned(string id)
    signal windowClosed()
    signal dateLinkRequested(string sourceCardId, string sourceItemId, string linkId, string defaultDate)
    signal calendarManagerRequested()

    visible: true
    // Transparent window corners: the rounded surface below is the only
    // painted background, so nothing square shows behind its border radius.
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
           | (win.pinned ? Qt.WindowStaysOnTopHint : 0)
    // Leave the picture-in-picture marker in the title so window rules can
    // match it (the Wayland app_id is shared by the whole process).
    title: {
        var list = win.entries || [];
        if (list.length === 1)
            return "Picture-in-Picture — " + (list[0].card
                ? (list[0].card.title || list[0].card.type || "Card") : "Card");
        return "Picture-in-Picture — " + list.length + " cards";
    }

    readonly property int toolbarHeight: 38
    readonly property int padding: 0
    readonly property int paneSpacing: 0
    readonly property int paneHeaderHeight: 32
    readonly property real cornerRadius: {
        try {
            var settings = JSON.parse(win.app.settingsJson);
            if (settings.card_radius !== undefined)
                return Math.max(0, Math.min(28, settings.card_radius));
        } catch (e) {}
        return win.th ? win.th.radiusCard : 8;
    }
    readonly property real screenW: win.screen ? win.screen.width : 1200
    readonly property real screenH: win.screen ? win.screen.height : 800
    readonly property real rowWidth: {
        var total = 0;
        var list = win.entries || [];
        for (var i = 0; i < list.length; i++)
            total += Math.max(280, list[i].width || 320) + (i > 0 ? win.paneSpacing : 0);
        return total;
    }
    readonly property real rowHeight: {
        var tallest = 220;
        var list = win.entries || [];
        for (var i = 0; i < list.length; i++)
            tallest = Math.max(tallest, Math.max(200, list[i].height || 240) + win.paneHeaderHeight);
        return tallest;
    }

    // Leave room for the window chrome and never grow past the screen; extra
    // cards stay reachable through the Flickable below.
    width: Math.min(Math.max(280, win.rowWidth + win.padding * 2),
                    win.screenW * 0.92)
    height: Math.min(Math.max(220, win.rowHeight + win.toolbarHeight + win.padding * 2),
                     win.screenH * 0.92)

    function returnToCanvas(id) {
        win.cardReturned(id);
    }

    onClosing: win.windowClosed()
    onPinnedChanged: {
        // Some platforms recreate the native window when the flags change.
        if (!win.visible) win.visible = true;
    }

    ListModel { id: cardModel }

    Component.onCompleted: syncEntries()
    onEntriesChanged: syncEntries()

    // Keep delegates alive while card data updates: only the card role is
    // replaced, so web views, timers and text editors are not recreated.
    function syncEntries() {
        var list = win.entries || [];
        for (var i = cardModel.count - 1; i >= 0; i--) {
            var id = cardModel.get(i).cardId;
            var keep = false;
            for (var j = 0; j < list.length; j++) {
                if (list[j].id === id) { keep = true; break; }
            }
            if (!keep) cardModel.remove(i);
        }
        for (var k = 0; k < list.length; k++) {
            var entry = list[k];
            var found = -1;
            for (var m = 0; m < cardModel.count; m++) {
                if (cardModel.get(m).cardId === entry.id) { found = m; break; }
            }
            if (found < 0) {
                cardModel.insert(Math.min(k, cardModel.count), {
                    "cardId": entry.id,
                    "card": entry.card,
                    "bodySource": entry.bodySource,
                    "paneWidth": entry.width,
                    "paneHeight": entry.height
                });
            } else {
                if (found !== k) cardModel.move(found, k, 1);
                cardModel.setProperty(k, "card", entry.card);
                cardModel.setProperty(k, "bodySource", entry.bodySource);
                cardModel.setProperty(k, "paneWidth", entry.width);
                cardModel.setProperty(k, "paneHeight", entry.height);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: win.cornerRadius
        color: win.th ? win.th.card : "#222222"
        border.width: win.th ? win.th.borderWidth : 1
        border.color: win.th ? win.th.borderStrong : "#444444"
    }

    Rectangle {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: win.toolbarHeight
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
            anchors.right: windowButtons.left
            anchors.rightMargin: win.th ? win.th.space2 : 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: win.th ? win.th.space2 : 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "app-window"
                size: win.th ? win.th.iconBody : 16
                color: win.th ? win.th.text2 : "#bbbbbb"
            }

            Text {
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var n = (win.entries || []).length;
                    return n === 1 ? "Picture-in-Picture"
                                   : "Picture-in-Picture · " + n + " cards";
                }
                color: win.th ? win.th.text : "#eeeeee"
                font.family: win.th ? win.th.fontFamily : "sans"
                font.pixelSize: win.th ? win.th.fontSizeSmall : 12
                font.weight: win.th ? win.th.fontWeightMedium : 500
                elide: Text.ElideRight
            }
        }

        Row {
            id: windowButtons
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
                ToolTip.text: win.pinned ? "Stop keeping these cards on top"
                                         : "Keep these cards on top"
            }

            Item {
                id: closeButton
                width: 26
                height: 26
                Accessible.role: Accessible.Button
                Accessible.name: "Return all cards to canvas"

                Rectangle {
                    anchors.fill: parent
                    radius: win.th ? win.th.radiusControl : 4
                    color: closeHover.hovered ? (win.th ? win.th.hover : "#333333") : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: "x"
                    size: win.th ? win.th.iconBody : 16
                    color: win.th ? win.th.text2 : "#bbbbbb"
                }
                HoverHandler { id: closeHover }
                TapHandler { onTapped: win.close() }
                ToolTip.visible: closeHover.hovered
                ToolTip.delay: 500
                ToolTip.text: "Return all cards to canvas"
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

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: toolbar.bottom
        anchors.bottom: parent.bottom
        anchors.margins: win.padding
        clip: true
        contentWidth: row.width
        contentHeight: row.height
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: row
            width: win.rowWidth
            height: win.rowHeight
            spacing: win.paneSpacing

            Repeater {
                model: cardModel

                delegate: Rectangle {
                    id: pane
                    required property string cardId
                    required property var card
                    required property string bodySource
                    required property real paneWidth
                    required property real paneHeight
                    required property int index

                    width: Math.max(280, paneWidth)
                    height: win.paneHeaderHeight + Math.max(200, paneHeight)
                    radius: 0
                    color: "transparent"

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: win.th ? win.th.borderWidth : 1
                        color: win.th ? win.th.border : "#333333"
                        visible: pane.index < cardModel.count - 1
                    }

                    Item {
                        id: paneHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: win.paneHeaderHeight

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
                            anchors.right: paneReturn.left
                            anchors.rightMargin: win.th ? win.th.space2 : 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: win.th ? win.th.space2 : 8

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: pane.card ? (pane.card.icon || "square") : "square"
                                size: win.th ? win.th.iconSmall : 14
                                color: win.th ? win.th.text2 : "#bbbbbb"
                            }

                            Text {
                                width: parent.width - 24
                                anchors.verticalCenter: parent.verticalCenter
                                text: pane.card
                                    ? (pane.card.title || pane.card.type || "Card") : "Card"
                                color: win.th ? win.th.text : "#eeeeee"
                                font.family: win.th ? win.th.fontFamily : "sans"
                                font.pixelSize: win.th ? win.th.fontSizeSmall : 12
                                font.weight: win.th ? win.th.fontWeightMedium : 500
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            id: paneReturn
                            width: 26
                            height: 26
                            anchors.right: parent.right
                            anchors.rightMargin: win.th ? win.th.space2 : 8
                            anchors.verticalCenter: parent.verticalCenter
                            Accessible.role: Accessible.Button
                            Accessible.name: "Back card to canvas"

                            Rectangle {
                                anchors.fill: parent
                                radius: win.th ? win.th.radiusControl : 4
                                color: paneReturnHover.hovered ? (win.th ? win.th.hover : "#333333") : "transparent"
                            }
                            Icon {
                                anchors.centerIn: parent
                                name: "undo-2"
                                size: win.th ? win.th.iconBody : 16
                                color: win.th ? win.th.text2 : "#bbbbbb"
                            }
                            HoverHandler { id: paneReturnHover }
                            TapHandler { onTapped: win.returnToCanvas(pane.cardId) }
                            ToolTip.visible: paneReturnHover.hovered
                            ToolTip.delay: 500
                            ToolTip.text: "Back card to canvas"
                        }
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: paneHeader.bottom
                        anchors.bottom: parent.bottom
                        clip: true

                        Loader {
                            id: bodyLoader
                            anchors.fill: parent
                            source: pane.bodySource
                            asynchronous: false

                            onLoaded: {
                                // Detach before assigning card: CardFrame's
                                // onCardChanged must not copy the canvas
                                // geometry over the pane-filling layout.
                                item.detached = true;
                                item.showChrome = false;
                                item.surfaceless = true;
                                item.app = Qt.binding(function () { return win.app; });
                                item.th = Qt.binding(function () { return win.th; });
                                item.gridId = Qt.binding(function () { return win.gridId; });
                                if (pane.card && pane.card.type === "website")
                                    item.webProfile = Qt.binding(function () { return win.webProfile; });

                                item.card = Qt.binding(function () { return pane.card; });

                                item.dateLinkRequested.connect(function (sourceCardId, sourceItemId, linkId, defaultDate) {
                                    win.dateLinkRequested(sourceCardId, sourceItemId, linkId, defaultDate);
                                });
                                item.calendarManagerRequested.connect(function () {
                                    win.calendarManagerRequested();
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}
