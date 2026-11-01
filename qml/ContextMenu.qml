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
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openAt(px, py) {
        x = Math.min(px, parent ? parent.width - width - 8 : px);
        y = Math.min(py, parent ? parent.height - height - 8 : py);
        open();
    }

    background: Rectangle {
        radius: 10
        color: root.th.menu
        border.width: 1
        border.color: root.th.border
    }

    contentItem: Column {
        spacing: 2

        Repeater {
            model: root.actions

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                property bool hoveredNow: false

                width: root.menuWidth - 12
                height: modelData.separator ? 9 : 32

                Rectangle {
                    visible: modelData.separator === true
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: root.th.border
                }

                Rectangle {
                    visible: modelData.separator !== true
                    anchors.fill: parent
                    radius: 6
                    color: row.hoveredNow ? root.th.hover : "transparent"
                }

                Row {
                    visible: modelData.separator !== true
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    spacing: 9

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.icon !== undefined && modelData.icon !== ""
                        name: modelData.icon || "square"
                        size: 14
                        color: modelData.danger ? root.th.danger : root.th.text2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label || ""
                        color: modelData.danger ? root.th.danger : root.th.text
                        font.family: root.th.fontFamily
                        font.pixelSize: 13
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
