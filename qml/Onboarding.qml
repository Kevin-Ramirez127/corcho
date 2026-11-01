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
        spacing: 18

        Rectangle {
            width: 40
            height: 40
            radius: 11
            color: root.th.accent
            Rectangle {
                anchors.centerIn: parent
                width: 14
                height: 14
                radius: 3
                color: root.th.accentInk
            }
        }

        Text {
            text: "Corcho"
            color: root.th.text
            font.family: root.th.fontFamily
            font.pixelSize: 30
            font.weight: 500
        }

        Text {
            width: parent.width
            text: "A canvas for thinking in cards. Notes, websites, tasks, timers and fragments live side by side on an infinite grid."
            color: root.th.text2
            font.family: root.th.fontFamily
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            lineHeight: 1.4
        }

        Text {
            width: parent.width
            text: "We intentionally do not include example grids. You will get the most out of it by exploring it yourself, without preconceptions."
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            lineHeight: 1.4
        }

        Row {
            spacing: 10

            AppButton {
                th: root.th
                text: "Start exploring"
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

        Text {
            text: "Press Ctrl + K for the Powerbar"
            color: root.th.muted
            font.family: "JetBrains Mono"
            font.pixelSize: 11
        }
    }
}
