import QtQuick

Item {
    id: root

    property var th

    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 20
    anchors.bottomMargin: 20
    width: 340
    height: column.height
    z: 500

    function show(kind, message) {
        model.append({ kind: kind, message: message });
    }

    ListModel { id: model }

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: model

            delegate: Rectangle {
                id: toast
                required property int index
                required property string kind
                required property string message

                width: column.width
                height: Math.max(40, label.implicitHeight + 20)
                radius: 10
                color: root.th.menu
                border.width: 1
                border.color: kind.indexOf("error") >= 0 ? root.th.danger : root.th.border
                opacity: 0

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 9

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: toast.kind.indexOf("error") >= 0 ? "triangle-alert" : "info"
                        size: 15
                        color: toast.kind.indexOf("error") >= 0 ? root.th.danger : root.th.accent
                    }
                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30
                        text: toast.message
                        color: root.th.text
                        font.family: root.th.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                NumberAnimation on opacity {
                    running: true
                    from: 0
                    to: 1
                    duration: 140
                }

                Timer {
                    interval: 4200
                    running: true
                    onTriggered: {
                        fade.start();
                    }
                }
                NumberAnimation {
                    id: fade
                    target: toast
                    property: "opacity"
                    to: 0
                    duration: 180
                    onFinished: if (toast.index < model.count) model.remove(toast.index)
                }
            }
        }
    }
}
