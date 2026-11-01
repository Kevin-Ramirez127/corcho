import QtQuick

CardFrame {
    id: root

    property var items: (card.items) ? card.items : []
    property bool changed: false

    function persist() {
        root.commit({ items: root.items });
    }

    function addItem(text) {
        if (text.trim() === "") return;
        var next = items.slice();
        next.push({ id: "i" + Date.now() + Math.floor(Math.random() * 999), text: text.trim(), done: false });
        items = next;
        persist();
    }

    function toggle(index) {
        var next = items.slice();
        next[index] = { id: next[index].id, text: next[index].text, done: !next[index].done };
        items = next;
        persist();
    }

    function remove(index) {
        var next = items.slice();
        next.splice(index, 1);
        items = next;
        persist();
    }

    readonly property int doneCount: {
        var n = 0;
        for (var i = 0; i < items.length; i++) if (items[i].done) n++;
        return n;
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: root.th.surfaceStrong

            Rectangle {
                width: parent.width * (root.items.length === 0 ? 0 : root.doneCount / root.items.length)
                height: parent.height
                radius: 2
                color: root.th.accent
                Behavior on width { NumberAnimation { duration: 160 } }
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 42
            clip: true
            spacing: 2
            model: root.items

            delegate: Item {
                id: checkItem
                required property var modelData
                required property int index
                property bool hoveredNow: false

                width: list.width
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: checkItem.hoveredNow ? root.th.hover : "transparent"
                }

                Icon {
                    id: box
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.done ? "circle-check" : "circle"
                    size: 16
                    color: modelData.done ? root.th.accent : root.th.muted
                }

                Text {
                    anchors.left: box.right
                    anchors.leftMargin: 9
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    elide: Text.ElideRight
                    color: modelData.done ? root.th.muted : root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: 13
                    font.strikeout: modelData.done
                }

                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    name: "x"
                    size: 12
                    color: root.th.muted
                    opacity: checkItem.hoveredNow ? 1 : 0
                }

                HoverHandler { id: rowHover
                    onHoveredChanged: checkItem.hoveredNow = hovered
                }
                TapHandler {
                    onTapped: root.toggle(index)
                    acceptedButtons: Qt.LeftButton
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.remove(index)
                }
            }
        }

        TextInput {
            id: addField
            width: parent.width
            height: 28
            color: root.th.text
            font.family: root.th.fontFamily
            font.pixelSize: 13
            clip: true
            onAccepted: {
                root.addItem(text);
                text = "";
            }
            Keys.onReturnPressed: {
                root.addItem(text);
                text = "";
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: addField.text.length === 0
                text: "Add a task"
                color: root.th.muted
                font: addField.font
            }
        }
    }
}
