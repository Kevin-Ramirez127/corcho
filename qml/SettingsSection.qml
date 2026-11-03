import QtQuick

Item {
    id: root

    property var th
    property string title: ""
    property string description: ""
    property string icon: ""
    default property alias rowData: content.data

    implicitWidth: 480
    implicitHeight: layout.implicitHeight + root.th.space5 * 2
    width: parent ? parent.width : implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: root.th.radiusPanel
        color: root.th.surface
        border.width: root.th.borderWidth
        border.color: root.th.border
    }

    Column {
        id: layout
        x: root.th.space5
        y: root.th.space5
        width: parent.width - root.th.space5 * 2
        spacing: root.th.space2

        Row {
            width: parent.width
            spacing: root.th.space2

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon !== ""
                name: root.icon
                size: root.th.iconBody
                color: root.th.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                font.weight: root.th.fontWeightMedium
            }
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

        Rectangle {
            width: parent.width
            height: root.th.borderWidth
            color: root.th.border
        }

        Column {
            id: content
            width: parent.width
            spacing: root.th.space1
        }
    }
}
