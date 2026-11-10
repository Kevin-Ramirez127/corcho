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
    signal committed(string value)
    activeFocusOnTab: true
    Accessible.role: Accessible.EditableText
    Accessible.name: root.placeholder

    // The wrapper can receive focus through Tab or forceActiveFocus(). Hand
    // it to the actual text input so typing works without a second click.
    onActiveFocusChanged: if (activeFocus && !input.activeFocus) input.forceActiveFocus()

    implicitHeight: root.inputHeight
    implicitWidth: 240

    Rectangle {
        anchors.fill: parent
        radius: root.th.radiusControl
        color: root.th.input
        border.width: root.th.borderWidth
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
        font.pixelSize: root.th.fontSizeBody
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        clip: true
        text: root.text
        onTextEdited: {
            root.text = text;
            root.edited(text);
        }
        onAccepted: {
            root.accepted();
            root.committed(text);
        }
        onActiveFocusChanged: if (!activeFocus) root.committed(text)
        Keys.onPressed: function (event) { root.keyPressed(event); }

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: root.placeholder
            color: root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
        }
    }
}
