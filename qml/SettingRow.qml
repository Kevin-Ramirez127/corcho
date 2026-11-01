import QtQuick

Item {
    id: root

    property var th
    property string title: ""
    property string description: ""
    default property alias control: slot.data

    implicitHeight: Math.max(44, textColumn.implicitHeight + 12)
    implicitWidth: 480
    width: parent ? parent.width : implicitWidth

    Column {
        id: textColumn
        anchors.left: parent.left
        anchors.right: slot.left
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.title
            color: root.th.text
            font.family: root.th.fontFamily
            font.pixelSize: 13
            font.weight: 500
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width
            visible: root.description !== ""
            text: root.description
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            lineHeight: 1.25
        }
    }

    Row {
        id: slot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
}
