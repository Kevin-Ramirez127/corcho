import QtQuick

Item {
    id: root

    property var th
    property string title: ""
    property string value: ""
    property string placeholder: ""
    property bool opened: false

    signal accepted(string text)
    signal cancelled()

    anchors.fill: parent
    visible: opened
    z: 600

    function open(titleText, initial, placeholderText) {
        title = titleText;
        value = initial;
        placeholder = placeholderText;
        opened = true;
        field.input.text = initial;
        field.input.forceActiveFocus();
        field.input.selectAll();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: root.cancelled() }
    }

    Rectangle {
        width: 380
        height: 142
        anchors.centerIn: parent
        radius: 14
        color: root.th.menu
        border.width: 1
        border.color: root.th.border

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: root.title
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: 14
                font.weight: 500
            }

            AppTextField {
                id: field
                width: parent.width
                th: root.th
                text: root.value
                placeholder: root.placeholder
                onAccepted: {
                    root.accepted(field.input.text);
                    root.opened = false;
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                AppButton {
                    th: root.th
                    text: "Cancel"
                    onClicked: {
                        root.opened = false;
                        root.cancelled();
                    }
                }
                AppButton {
                    th: root.th
                    text: "Save"
                    variant: "solid"
                    onClicked: {
                        root.accepted(field.input.text);
                        root.opened = false;
                    }
                }
            }
        }
    }
}
