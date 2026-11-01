import QtQuick

CardFrame {
    id: root

    function wrap(before, after) {
        var start = editor.selectionStart;
        var end = editor.selectionEnd;
        var selected = editor.selectedText;
        editor.remove(start, end);
        editor.insert(start, before + selected + after);
        editor.cursorPosition = start + before.length + selected.length + after.length;
        editor.forceActiveFocus();
    }

    function prefixLine(prefix) {
        var pos = editor.cursorPosition;
        var lineStart = editor.text.lastIndexOf("\n", pos - 1) + 1;
        editor.insert(lineStart, prefix);
        editor.forceActiveFocus();
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Row {
            spacing: 2

            Repeater {
                model: [
                    { icon: "bold", run: function () { root.wrap("**", "**"); } },
                    { icon: "italic", run: function () { root.wrap("_", "_"); } },
                    { icon: "heading", run: function () { root.prefixLine("## "); } },
                    { icon: "list", run: function () { root.prefixLine("- "); } },
                    { icon: "list-ordered", run: function () { root.prefixLine("1. "); } },
                    { icon: "quote", run: function () { root.prefixLine("> "); } },
                    { icon: "code", run: function () { root.wrap("`", "`"); } },
                    { icon: "link", run: function () { root.wrap("[", "](https://)"); } }
                ]

                delegate: Item {
                    id: toolItem
                    required property var modelData
                    width: 26
                    height: 24
                    property bool hoveredNow: false

                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: toolItem.hoveredNow ? root.th.hover : "transparent"
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: modelData.icon
                        size: 13
                        color: root.th.text2
                    }
                    HoverHandler { id: h
                        onHoveredChanged: toolItem.hoveredNow = hovered
                    }
                    TapHandler { onTapped: modelData.run() }
                }
            }
        }

        TextEdit {
            id: editor
            width: parent.width
            height: parent.height - 32
            text: root.card.text || ""
            color: root.th.text
            selectionColor: root.th.accent
            selectedTextColor: root.th.accentInk
            font.family: root.th.fontFamily
            font.pixelSize: 13
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            bottomPadding: 6
            clip: true
            onActiveFocusChanged: if (!activeFocus) root.commit(null, text)
            Keys.onPressed: function (event) {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                    root.commit(null, editor.text);
                    event.accepted = true;
                }
            }

            Text {
                anchors.fill: parent
                visible: editor.text.length === 0
                text: "Write something"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }
    }
}
