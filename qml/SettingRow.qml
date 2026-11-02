import QtQuick

Item {
    id: root

    property var th
    property string title: ""
    property string description: ""
    default property alias control: slot.data

    implicitHeight: Math.max(48, textColumn.implicitHeight + 16)
    implicitWidth: 480
    width: parent ? parent.width : implicitWidth

    Column {
        id: textColumn
        anchors.left: parent.left
        anchors.right: slot.left
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.th.space1
        Text {
            width: parent.width
            text: root.title
            color: root.th.text
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
            font.weight: root.th.fontWeightMedium
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width
            visible: root.description !== ""
            text: root.description
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
            wrapMode: Text.WordWrap
            lineHeight: 1.25
        }
    }

    Row {
        id: slot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.th.space2
    }
}
