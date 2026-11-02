import QtQuick

CardFrame {
    id: root

    property string prompt: (card.prompt) || ""
    property string context: (card.context) || ""
    property string output: (card.lastResult) || ""
    property string streamId: ""
    property bool busy: false
    property string errorText: ""

    function settings() {
        try { return JSON.parse(root.app.settingsJson); } catch (e) { return ({}); }
    }

    function run() {
        var s = settings();
        var provider = s.aiProvider || "claude";
        var model = (s.aiModel && s.aiModel[provider]) || "";
        root.busy = true;
        root.errorText = "";
        root.output = "";
        root.commit({ prompt: root.prompt, context: root.context });
        root.streamId = root.app.aiSend(provider, model, root.prompt, root.context);
    }

    Connections {
        target: root.app
        function onAiChunk(id, chunk) {
            if (id === root.streamId) root.output += chunk;
        }
        function onAiDone(id, full) {
            if (id !== root.streamId) return;
            root.busy = false;
            root.output = full;
            root.commit({ prompt: root.prompt, context: root.context, lastResult: root.output });
        }
        function onAiError(id, message) {
            if (id !== root.streamId) return;
            root.busy = false;
            root.errorText = message;
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.th.space2
        TextEdit {
            id: promptEdit
            width: parent.width
            height: 64
            text: root.prompt
            color: root.th.text
            selectionColor: root.th.accent
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            clip: true
            onActiveFocusChanged: if (!activeFocus) root.commit({ prompt: text, context: root.context })

            Text {
                anchors.fill: parent
                visible: promptEdit.text.length === 0
                text: "Prompt"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }

        Row {
            width: parent.width
            spacing: root.th.space2
            AppButton {
                th: root.th
                icon: root.busy ? "refresh-cw" : "play"
                text: root.busy ? "Thinking" : "Run"
                variant: "solid"
                enabledButton: !root.busy && root.prompt.trim() !== ""
                onClicked: root.run()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var s = root.settings();
                    var p = s.aiProvider || "claude";
                    return (s.aiModel && s.aiModel[p]) ? s.aiModel[p] : p;
                }
                color: root.th.muted
                font.family: root.th.fontMono
                font.pixelSize: root.th.fontSizeSmall
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.th.border
        }

        TextEdit {
            width: parent.width
            height: parent.height - 116
            text: root.busy ? root.output + " ..." : (root.errorText !== "" ? root.errorText : root.output)
            readOnly: true
            selectByMouse: true
            color: root.errorText !== "" ? root.th.danger : root.th.text2
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
            wrapMode: TextEdit.Wrap
            clip: true

            Text {
                anchors.fill: parent
                visible: parent.text.length === 0
                text: "Output appears here"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }
    }
}
