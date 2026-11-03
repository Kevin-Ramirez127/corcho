import QtQuick

Item {
    id: root

    property var app
    property var th
    property bool opened: false

    signal startExploring()
    signal openBackup()

    function open() { opened = true; }

    anchors.fill: parent
    visible: opened
    z: 450

    Rectangle {
        anchors.fill: parent
        color: root.th.bg
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(560, root.width - 80)
        spacing: root.th.space5
        Icon {
            name: "pin"
            size: root.th.iconPage
            color: root.th.accent
        }

        Text {
            text: "Corcho"
            color: root.th.text
            font.family: root.th.brandFont
            font.pixelSize: root.th.fontSizeDisplay
            font.weight: Font.Bold
        }

        Text {
            width: parent.width
            text: "A canvas for thinking in cards. Notes, websites, tasks, timers and calendars live side by side on an infinite grid."
            color: root.th.text2
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSubtitle
            wrapMode: Text.WordWrap
            lineHeight: 1.45
        }

        Text {
            width: parent.width
            text: "We intentionally do not include example grids. You will get the most out of it by exploring it yourself, without preconceptions."
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
            wrapMode: Text.WordWrap
            lineHeight: 1.45
        }

        Row {
            spacing: root.th.space3
            AppButton {
                th: root.th
                text: "Begin"
                variant: "solid"
                onClicked: root.startExploring()
            }
            AppButton {
                th: root.th
                icon: "download"
                text: "Import a backup"
                onClicked: root.openBackup()
            }
        }

        Row {
            spacing: root.th.space2
            Keycap { th: root.th; text: "Ctrl K" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Launcher"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }
    }
}
