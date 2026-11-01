import QtQuick

Item {
    id: root

    property var th
    property string text: ""
    property string placeholder: ""
    property bool password: false
    property int inputHeight: 36
    property alias input: input

    signal edited(string value)
    signal accepted()
    signal keyPressed(var event)

    implicitHeight: inputHeight
    implicitWidth: 240

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.th.input
        border.width: 1
        border.color: input.activeFocus ? root.th.accent : root.th.border
        Behavior on border.color { ColorAnimation { duration: 110 } }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        verticalAlignment: TextInput.AlignVCenter
        color: root.th.text
        selectionColor: root.th.accent
        selectedTextColor: root.th.accentInk
        font.family: root.th.fontFamily
        font.pixelSize: 13
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        clip: true
        text: root.text
        onTextEdited: {
            root.text = text;
            root.edited(text);
        }
        onAccepted: root.accepted()
        Keys.onPressed: function (event) { root.keyPressed(event); }

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: root.placeholder
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: 13
        }
    }
}
