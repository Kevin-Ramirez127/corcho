import QtQuick

CardFrame {
    id: root

    property string script: (card.script) || ""
    property string output: (card.lastOutput) || ""
    property bool ok: true

    function run() {
        var result = JSON.parse(root.app.runScript(root.script));
        root.ok = !!result.ok;
        root.output = result.ok
            ? "exit " + result.code + "  ·  " + result.ms + "ms\n\n" + (result.stdout || "") + (result.stderr || "")
            : "error: " + (result.error || result.stderr || "failed");
        root.commit({ script: root.script, lastOutput: root.output });
    }

    Column {
        anchors.fill: parent
        spacing: 8

        TextEdit {
            id: editor
            width: parent.width
            height: 82
            text: root.script
            color: root.th.text
            selectionColor: root.th.accent
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            clip: true
            onActiveFocusChanged: if (!activeFocus) root.commit({ script: text, lastOutput: root.output })

            Text {
                anchors.fill: parent
                visible: editor.text.length === 0
                text: "/bin/sh script"
                color: root.th.muted
                font.family: "JetBrains Mono"
                font.pixelSize: 12
            }
        }

        AppButton {
            th: root.th
            icon: "play"
            text: "Run"
            variant: "solid"
            enabledButton: root.script.trim() !== ""
            onClicked: root.run()
        }

        TextEdit {
            width: parent.width
            height: parent.height - 128
            text: root.output
            readOnly: true
            selectByMouse: true
            color: root.ok ? root.th.text2 : root.th.danger
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            wrapMode: TextEdit.WrapAnywhere
            clip: true

            Text {
                anchors.fill: parent
                visible: parent.text.length === 0
                text: "Output appears here"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: 12
            }
        }
    }
}
