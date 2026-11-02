import QtQuick

Item {
    id: root

    property var th
    property string text: ""

    implicitWidth: label.implicitWidth + root.th.space3
    implicitHeight: root.th.keycapHeight

    Rectangle {
        anchors.fill: parent
        radius: root.th.radiusMicro
        color: root.th.input
        border.width: root.th.borderWidth
        border.color: root.th.border
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.th.muted
        font.family: root.th.fontMono
        font.pixelSize: root.th.fontSizeSmall
    }
}
