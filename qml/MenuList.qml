import QtQuick
import QtQuick.Controls
import "OverlayState.js" as OverlayState

Popup {
    id: menu

    property var th
    property var items: []
    property var stack: []
    property real areaW: 0
    property real areaH: 0

    signal chosen(string action)

    width: 224
    padding: 8
    // Modal popups make the overlay consume tablet events before the pen
    // catcher below can see them. Keep the dim for the same appearance.
    modal: false
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property int currentIndex: 0

    function firstSelectable() {
        for (var i = 0; i < items.length; i++)
            if (items[i] && items[i].separator !== true) return i;
        return 0;
    }

    function moveCurrent(delta) {
        if (items.length === 0) return;
        var i = currentIndex;
        for (var n = 0; n < items.length; n++) {
            i = (i + delta + items.length) % items.length;
            if (items[i] && items[i].separator !== true) {
                currentIndex = i;
                return;
            }
        }
    }

    function estimatedHeight() {
        var total = padding * 2;
        for (var i = 0; i < items.length; i++) {
            var data = items[i];
            if (!data) continue;
            if (i > 0) total += th.spaceHalf;
            total += data.separator === true ? th.space2 : th.menuItemHeight;
        }
        return total;
    }

    function place(px, py) {
        var w = areaW > 0 ? areaW : Screen.width;
        var h = areaH > 0 ? areaH : Screen.height;
        var ph = Math.max(height, estimatedHeight());
        x = Math.max(4, Math.min(px, w - width - 4));
        y = Math.max(4, Math.min(py, h - ph - 4));
    }

    function showAt(px, py) {
        stack = [];
        place(px, py);
        currentIndex = firstSelectable();
        open();
    }

    function push(label, children) {
        stack = stack.concat([{ label: label, items: items }]);
        items = [{ label: label, icon: "chevron-left", action: "__back" }, { separator: true, label: "" }].concat(children);
        currentIndex = firstSelectable();
    }

    function back() {
        if (stack.length === 0) return;
        items = stack[stack.length - 1].items;
        stack = stack.slice(0, stack.length - 1);
        currentIndex = firstSelectable();
    }

    // Popup.CloseOnPressOutside only tracks mouse and touch, so this
    // full-window catcher closes the menu when a stylus taps outside it.
    // It is created directly in the overlay so that it is not culled by
    // the popup's content positioner while the popup is closed.
    property Item penCatcher: null
    property bool countedOpen: false

    Component {
        id: penCatcherComponent

        Item {
            objectName: "penCatcher"
            anchors.fill: parent
            z: menu.z - 1

            // Mouse and touch clicks outside the menu close it and stop
            // there. Without this the same click also reached whatever card
            // sat underneath, so choosing a dropdown option could toggle a
            // checklist task at the same screen position.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                preventStealing: true
                onPressed: function (mouse) { mouse.accepted = true; }
                onClicked: menu.close()
                onWheel: function (wheel) { wheel.accepted = true; }
            }

            TapHandler {
                acceptedPointerTypes: PointerDevice.AllDevices
                // Take the event so it cannot activate the control underneath
                // and immediately reopen the menu.
                gesturePolicy: TapHandler.WithinBounds
                onTapped: menu.close()
            }
        }
    }

    onOpened: {
        if (!countedOpen) {
            OverlayState.menuOpened();
            countedOpen = true;
        }
        var overlay = Overlay.overlay;
        if (overlay && !penCatcher)
            penCatcher = penCatcherComponent.createObject(overlay);
    }

    onClosed: {
        if (countedOpen) {
            OverlayState.menuClosed();
            countedOpen = false;
        }
        if (penCatcher) {
            penCatcher.destroy();
            penCatcher = null;
        }
    }

    Component.onDestruction: {
        if (countedOpen)
            OverlayState.menuClosed();
        if (penCatcher)
            penCatcher.destroy();
    }

    function activate(index) {
        var data = items[index];
        if (!data || data.separator === true) return;
        if (data.children !== undefined && data.children.length > 0) {
            push(data.label || "", data.children);
            return;
        }
        if (data.action === "__back") {
            back();
            return;
        }
        close();
        chosen(data.action || "");
    }

    background: Rectangle {
        radius: menu.th.radiusCard
        color: menu.th.menu
        border.width: menu.th.borderWidth
        border.color: menu.th.border
    }

    // Keys attached to a Popup are ignored because Popup is not an Item.
    // Handle navigation on a focus scope inside the content instead.
    contentItem: FocusScope {
        id: menuContent
        implicitWidth: contentColumn.implicitWidth
        implicitHeight: contentColumn.implicitHeight
        focus: true
        Keys.onUpPressed: menu.moveCurrent(-1)
        Keys.onDownPressed: menu.moveCurrent(1)
        Keys.onReturnPressed: menu.activate(menu.currentIndex)
        Keys.onEnterPressed: menu.activate(menu.currentIndex)
        Keys.onEscapePressed: {
            if (menu.stack.length > 0) menu.back();
            else menu.close();
        }

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: menu.th.spaceHalf
            Repeater {
                model: menu.items

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    property var actionData: modelData || ({})
                    property bool hoveredNow: false
                    property bool hasChildren: actionData.children !== undefined && actionData.children.length > 0
                    readonly property bool dangerFill: actionData.dangerFill === true
                    readonly property bool highlighted: hoveredNow || menu.currentIndex === index

                    width: menu.width - menu.padding * 2
                    height: actionData.separator ? menu.th.space2 : menu.th.menuItemHeight
                    Accessible.role: actionData.separator === true ? Accessible.Separator : Accessible.MenuItem
                    Accessible.name: actionData.separator === true ? "" : (actionData.label || "")
                    Accessible.selected: menu.currentIndex === row.index
                    Accessible.onPressAction: if (actionData.separator !== true) menu.activate(row.index)

                    Rectangle {
                        visible: actionData.separator === true
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: menu.th.borderWidth
                        color: menu.th.border
                    }

                    Rectangle {
                        visible: actionData.separator !== true
                        anchors.fill: parent
                        radius: menu.th.radiusKeycap
                        color: row.dangerFill
                            ? (row.highlighted ? Qt.darker(menu.th.danger, 1.15) : menu.th.danger)
                            : (row.highlighted ? menu.th.hover : "transparent")
                    }

                    Row {
                        visible: actionData.separator !== true
                        anchors.fill: parent
                        anchors.leftMargin: menu.th.space3
                        spacing: menu.th.space2
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: actionData.icon !== undefined && actionData.icon !== ""
                            name: actionData.icon || "square"
                            size: menu.th.iconBody
                            color: row.dangerFill
                                ? menu.th.bg
                                : (actionData.danger ? menu.th.danger : menu.th.text2)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - menu.th.space3 * 2 - menu.th.iconBody - menu.th.space2
                            text: actionData.label || ""
                            color: row.dangerFill
                                ? menu.th.bg
                                : (actionData.danger ? menu.th.danger : menu.th.text)
                            font.family: menu.th.fontFamily
                            font.pixelSize: menu.th.fontSizeBody
                            elide: Text.ElideRight
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.hasChildren
                            name: "chevron-right"
                            size: 14
                            color: row.dangerFill ? menu.th.bg : menu.th.text2
                        }
                    }

                    HoverHandler { onHoveredChanged: row.hoveredNow = hovered }

                    MouseArea {
                        anchors.fill: parent
                        enabled: actionData.separator !== true
                        onClicked: menu.activate(row.index)
                    }
                }
            }
        }
    }
}
