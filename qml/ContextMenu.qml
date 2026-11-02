import QtQuick
import QtQuick.Controls

Popup {
    id: root

    property var th
    property var actions: []
    property real menuWidth: 232

    signal triggered(int index)
    property bool rowHovered: false

    width: menuWidth
    padding: 8
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openAt(px, py) {
        x = Math.min(px, parent ? parent.width - width - 8 : px);
        y = Math.min(py, parent ? parent.height - height - 8 : py);
        open();
    }

    background: Rectangle {
        radius: root.th.radiusCard
        color: root.th.menu
        border.width: root.th.borderWidth
        border.color: root.th.border
    }

    contentItem: Column {
        spacing: root.th.spaceHalf
        Repeater {
            model: root.actions

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                property bool hoveredNow: false

                width: root.menuWidth - 12
                height: modelData.separator ? root.th.space2 : root.th.menuItemHeight

                Rectangle {
                    visible: modelData.separator === true
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: root.th.borderWidth
                    color: root.th.border
                }

                Rectangle {
                    visible: modelData.separator !== true
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: row.hoveredNow ? root.th.hover : "transparent"
                }

                Row {
                    visible: modelData.separator !== true
                    anchors.fill: parent
                    anchors.leftMargin: root.th.space3
                    spacing: root.th.space2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.icon !== undefined && modelData.icon !== ""
                        name: modelData.icon || "square"
                        size: root.th.iconBody
                        color: modelData.danger ? root.th.danger : root.th.text2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label || ""
                        color: modelData.danger ? root.th.danger : root.th.text
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeBody
                    }
                }

                HoverHandler { id: hover
                    onHoveredChanged: row.hoveredNow = hovered
                }

                TapHandler {
                    enabled: modelData.separator !== true
                    onTapped: {
                        root.close();
                        root.triggered(index);
                    }
                }
            }
        }
    }
}
