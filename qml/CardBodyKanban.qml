import QtQuick

CardFrame {
    id: root

    property var columns: {
        var c = card.columns ? card.columns : [];
        if (c.length === 0) {
            c = [
                { id: "todo", title: "To do", items: [] },
                { id: "doing", title: "In progress", items: [] },
                { id: "done", title: "Done", items: [] }
            ];
        }
        return c;
    }

    function persist(next) {
        columns = next;
        root.commit({ columns: next });
    }

    function addItem(colIndex, text) {
        if (text.trim() === "") return;
        var next = JSON.parse(JSON.stringify(columns));
        next[colIndex].items.push({ id: "k" + Date.now() + Math.floor(Math.random() * 999), text: text.trim() });
        persist(next);
    }

    function moveTo(colIndex, itemIndex, targetCol) {
        if (targetCol === colIndex || targetCol < 0 || targetCol >= columns.length) return;
        var next = JSON.parse(JSON.stringify(columns));
        var item = next[colIndex].items.splice(itemIndex, 1)[0];
        next[targetCol].items.push(item);
        persist(next);
    }

    function move(colIndex, itemIndex, dir) {
        var next = JSON.parse(JSON.stringify(columns));
        var target = colIndex + dir;
        if (target < 0 || target >= next.length) return;
        var item = next[colIndex].items.splice(itemIndex, 1)[0];
        next[target].items.push(item);
        persist(next);
    }

    function remove(colIndex, itemIndex) {
        var next = JSON.parse(JSON.stringify(columns));
        next[colIndex].items.splice(itemIndex, 1);
        persist(next);
    }

    Row {
        id: columnsRow
        anchors.fill: parent
        spacing: 10

        Repeater {
            model: root.columns

            delegate: Item {
                id: column
                required property var modelData
                required property int index

                width: (parent.width - 20) / 3
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: root.th.surface
                    border.width: 1
                    border.color: root.th.border
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text {
                        text: modelData.title
                        color: root.th.text2
                        font.family: root.th.fontFamily
                        font.pixelSize: 11
                        font.weight: 500
                        font.letterSpacing: 0.4
                    }

                    ListView {
                        id: columnList
                        width: parent.width
                        height: parent.height - 48
                        clip: true
                        spacing: 4
                        model: modelData.items

                        delegate: Item {
                            id: kanbanItem
                            required property var modelData
                            required property int index
                            property bool hoveredNow: false

                            width: columnList.width
                            height: 34

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: kanbanItem.hoveredNow ? root.th.hover : root.th.surfaceStrong
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.text
                                color: root.th.text
                                font.family: root.th.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                opacity: kanbanItem.hoveredNow ? 1 : 0

                                Icon {
                                    name: "chevron-left"
                                    size: 11
                                    color: root.th.muted
                                    TapHandler { onTapped: root.move(column.index, index, -1) }
                                }
                                Icon {
                                    name: "chevron-right"
                                    size: 11
                                    color: root.th.muted
                                    TapHandler { onTapped: root.move(column.index, index, 1) }
                                }
                                Icon {
                                    name: "x"
                                    size: 11
                                    color: root.th.muted
                                    TapHandler { onTapped: root.remove(column.index, index) }
                                }
                            }

                            HoverHandler { id: itemHover
                                onHoveredChanged: kanbanItem.hoveredNow = hovered
                            }
                        }
                    }

                    TextInput {
                        id: addInput
                        width: parent.width
                        height: 24
                        color: root.th.text
                        font.family: root.th.fontFamily
                        font.pixelSize: 12
                        clip: true
                        onAccepted: {
                            root.addItem(column.index, text);
                            text = "";
                        }
                        Keys.onReturnPressed: {
                            root.addItem(column.index, text);
                            text = "";
                        }
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: addInput.text.length === 0
                            text: "+ Add"
                            color: root.th.muted
                            font: addInput.font
                        }
                    }
                }
            }
        }
    }
}
