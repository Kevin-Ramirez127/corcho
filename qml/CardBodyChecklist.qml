import QtQuick

CardFrame {
    id: root

    property var items: (card.items) ? card.items : []
    property bool changed: false

    readonly property var links: {
        try { return (JSON.parse(root.app.calendarJson).dateLinks || []); }
        catch (e) { return []; }
    }

    function linkFor(itemId) {
        for (var i = 0; i < links.length; i++)
            if (links[i].sourceCardId === root.card.id && links[i].sourceItemId === itemId)
                return links[i];
        return null;
    }

    function shortDate(key) {
        var p = key.split("-");
        if (p.length !== 3) return key;
        var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
        return d.toLocaleDateString(Qt.locale(), "MMM d");
    }

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
        spacing: root.th.space2
        Rectangle {
            width: parent.width
            height: 4
            radius: root.th.radiusHairline
            color: root.th.surfaceStrong

            Rectangle {
                width: parent.width * (root.items.length === 0 ? 0 : root.doneCount / root.items.length)
                height: parent.height
                radius: root.th.radiusHairline
                color: root.th.accent
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 42
            clip: true
            spacing: root.th.spaceHalf
            model: root.items

            delegate: Item {
                id: checkItem
                required property var modelData
                required property int index
                property bool hoveredNow: false
                readonly property var link: root.linkFor(modelData.id)

                width: list.width
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: checkItem.hoveredNow ? root.th.hover : "transparent"
                }

                Icon {
                    id: box
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.done ? "circle-check" : "circle"
                    size: root.th.iconBody
                    color: modelData.done ? root.th.accent : root.th.muted
                }

                Row {
                    id: rightRow
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.th.space1
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: checkItem.link !== null
                        text: checkItem.link ? root.shortDate(checkItem.link.date) : ""
                        color: root.th.accent
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeMicro
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "calendar"
                        size: root.th.iconSmall
                        color: checkItem.link !== null ? root.th.accent : root.th.muted
                        opacity: (checkItem.link !== null || checkItem.hoveredNow) ? 1 : 0
                        TapHandler {
                            onTapped: root.dateLinkRequested(
                                root.card.id,
                                modelData.id,
                                checkItem.link ? checkItem.link.id : "",
                                checkItem.link ? checkItem.link.date : "")
                        }
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        size: root.th.iconSmall
                        color: root.th.muted
                        opacity: checkItem.hoveredNow ? 1 : 0
                    }
                }

                Text {
                    anchors.left: box.right
                    anchors.leftMargin: 9
                    anchors.right: rightRow.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    elide: Text.ElideRight
                    color: modelData.done ? root.th.muted : root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    font.strikeout: modelData.done
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
            font.pixelSize: root.th.fontSizeSmall
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
