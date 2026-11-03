import QtQuick
import QtQuick.Controls

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
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function place(px, py) {
        var w = areaW > 0 ? areaW : Screen.width;
        var h = areaH > 0 ? areaH : Screen.height;
        x = Math.max(4, Math.min(px, w - width - 4));
        y = Math.max(4, Math.min(py, h - height - 4));
    }

    function showAt(px, py) {
        stack = [];
        place(px, py);
        open();
    }

    function push(label, children) {
        stack = stack.concat([{ label: label, items: items }]);
        items = [{ label: label, icon: "chevron-left", action: "__back" }, { separator: true, label: "" }].concat(children);
    }

    function back() {
        if (stack.length === 0) return;
        items = stack[stack.length - 1].items;
        stack = stack.slice(0, stack.length - 1);
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

    contentItem: Column {
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

                width: menu.width - menu.padding * 2
                height: actionData.separator ? menu.th.space2 : menu.th.menuItemHeight

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
                    color: row.hoveredNow ? menu.th.hover : "transparent"
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
                        color: actionData.danger ? menu.th.danger : menu.th.text2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - menu.th.space3 * 2 - menu.th.iconBody - menu.th.space2
                        text: actionData.label || ""
                        color: actionData.danger ? menu.th.danger : menu.th.text
                        font.family: menu.th.fontFamily
                        font.pixelSize: menu.th.fontSizeBody
                        elide: Text.ElideRight
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.hasChildren
                        name: "chevron-right"
                        size: 14
                        color: menu.th.text2
                    }
                }

                HoverHandler { onHoveredChanged: row.hoveredNow = hovered }

                TapHandler {
                    enabled: actionData.separator !== true
                    onTapped: menu.activate(row.index)
                }
            }
        }
    }
}
