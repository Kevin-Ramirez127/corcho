import QtQuick
import "OverlayState.js" as OverlayState

CardFrame {
    id: root

    property var items: (root.card && root.card.items) ? root.card.items : []
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

    // Called by the canvas when this card was just created.
    function focusBody() {
        addField.forceActiveFocus();
    }

    // Pointer handlers on overlapping cards can all receive the same tap, so
    // only the card that is actually on top at the event position may react.
    function canInteractAt(sceneX, sceneY) {
        if (!root.card) return false;
        // A dropdown or context menu floating over this card owns the click.
        if (OverlayState.openMenus > 0) return false;
        return !root.canvasView
            || root.canvasView.isTopCardAtScene(root.card.id, sceneX, sceneY);
    }

    function addItem(text) {
        if (text.trim() === "") return;
        var next = items.slice();
        next.push({ id: "i" + Date.now() + Math.floor(Math.random() * 999), text: text.trim(), done: false });
        items = next;
        persist();
    }

    function toggle(index) {
        if (index < 0 || index >= items.length) return;
        var next = items.slice();
        next[index] = { id: next[index].id, text: next[index].text, done: !next[index].done };
        items = next;
        persist();
    }

    function remove(index) {
        if (index < 0 || index >= items.length) return;
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
            id: progressBar
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
            height: Math.max(0, parent.height - progressBar.height - addBox.height
                                - (root.th ? root.th.space2 : 8) * 2)
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
                height: Math.max(30, taskText.implicitHeight + 8)

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
                        objectName: "checklistDate_" + index
                        anchors.verticalCenter: parent.verticalCenter
                        name: "calendar"
                        size: root.th.iconSmall
                        color: checkItem.link !== null ? root.th.accent : root.th.muted
                        opacity: (checkItem.link !== null || checkItem.hoveredNow) ? 1 : 0
                        TapHandler {
                            onTapped: {
                                if (!root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                                    return;
                                root.dateLinkRequested(
                                    root.card.id,
                                    modelData.id,
                                    checkItem.link ? checkItem.link.id : "",
                                    checkItem.link ? checkItem.link.date : "");
                            }
                        }
                    }
                    Icon {
                        objectName: "checklistRemove_" + index
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        size: root.th.iconSmall
                        color: root.th.muted
                        opacity: checkItem.hoveredNow ? 1 : 0
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: {
                                if (root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                                    root.remove(index);
                            }
                        }
                    }
                }

                Text {
                    id: taskText
                    objectName: "checklistTaskText_" + index
                    anchors.left: box.right
                    anchors.leftMargin: 9
                    anchors.right: rightRow.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    wrapMode: Text.Wrap
                    color: modelData.done ? root.th.muted : root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    font.strikeout: modelData.done
                }

                // The done toggle only covers the row before the date and
                // remove controls, so those buttons never mark the task done.
                Item {
                    anchors.left: parent.left
                    anchors.right: rightRow.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                            if (!root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                                return;
                            root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y);
                            root.toggle(index);
                        }
                    }
                }

                HoverHandler { id: rowHover
                    onHoveredChanged: checkItem.hoveredNow = hovered
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        if (root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                            root.remove(index);
                    }
                }
            }
        }

        // The add-task field uses the same surface, radius and focus ring as
        // the other text inputs in the app, and grows when a long task wraps.
        Rectangle {
            id: addBox
            objectName: "checklistAddBox"
            width: parent.width
            height: Math.max(root.th ? root.th.controlHeight : 32, addField.contentHeight + 10)
            radius: root.th.radiusControl
            color: root.th.input
            border.width: root.th.borderWidth
            border.color: addField.activeFocus ? root.th.accent : root.th.border
            Behavior on border.color { ColorAnimation { duration: 110 } }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: addField.forceActiveFocus()
            }

            TextInput {
                id: addField
                objectName: "checklistAddField"
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
                selectionColor: root.th.accent
                selectedTextColor: root.th.accentInk
                wrapMode: TextInput.Wrap
                verticalAlignment: TextInput.AlignTop
                clip: true
                onAccepted: {
                    root.addItem(text);
                    text = "";
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y)
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
}
