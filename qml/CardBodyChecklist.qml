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

    // Undone tasks come first, followed by completed ones. Group headings are
    // only emitted for non-empty groups.
    readonly property var rows: {
        var pending = [];
        var completed = [];
        for (var i = 0; i < items.length; i++) {
            var row = { header: false, item: items[i], index: i };
            if (items[i].done) completed.push(row);
            else pending.push(row);
        }
        var out = [];
        if (pending.length > 0) {
            out.push({ header: true, label: "Undone" });
            out = out.concat(pending);
        }
        if (completed.length > 0) {
            out.push({ header: true, label: "Done" });
            out = out.concat(completed);
        }
        return out;
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
            model: root.rows

            delegate: Item {
                id: checkItem
                required property var modelData
                required property int index
                property bool hoveredNow: false
                readonly property bool isHeader: modelData && modelData.header === true
                readonly property var task: checkItem.isHeader ? null : modelData.item
                readonly property int taskIndex: checkItem.isHeader ? -1 : modelData.index
                readonly property var link: checkItem.task ? root.linkFor(checkItem.task.id) : null

                width: list.width
                height: checkItem.isHeader ? 22 : Math.max(30, taskText.implicitHeight + 8)

                Text {
                    objectName: "checklistGroupHeader_" + (modelData.label || "")
                    visible: checkItem.isHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label || ""
                    color: root.th.text2
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeMicro
                    font.weight: root.th.fontWeightMedium
                }

                Rectangle {
                    visible: !checkItem.isHeader
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: checkItem.hoveredNow ? root.th.hover : "transparent"
                }

                Icon {
                    id: box
                    visible: !checkItem.isHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    name: checkItem.task && checkItem.task.done ? "circle-check" : "circle"
                    size: root.th.iconBody
                    color: checkItem.task && checkItem.task.done ? root.th.accent : root.th.muted
                }

                Row {
                    id: rightRow
                    visible: !checkItem.isHeader
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
                        objectName: "checklistDate_" + checkItem.taskIndex
                        anchors.verticalCenter: parent.verticalCenter
                        name: "calendar"
                        size: root.th.iconSmall
                        color: checkItem.link !== null ? root.th.accent : root.th.muted
                        opacity: (checkItem.link !== null || checkItem.hoveredNow) ? 1 : 0
                        CardTapHandler {
                            onAction: {
                                if (!root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                                    return;
                                root.dateLinkRequested(
                                    root.card.id,
                                    checkItem.task.id,
                                    checkItem.link ? checkItem.link.id : "",
                                    checkItem.link ? checkItem.link.date : "");
                            }
                        }
                    }
                    Icon {
                        objectName: "checklistRemove_" + checkItem.taskIndex
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        size: root.th.iconSmall
                        color: root.th.muted
                        opacity: checkItem.hoveredNow ? 1 : 0
                        CardTapHandler {
                            acceptedButtons: Qt.LeftButton
                            onAction: {
                                if (root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                                    root.remove(checkItem.taskIndex);
                            }
                        }
                    }
                }

                Text {
                    id: taskText
                    objectName: "checklistTaskText_" + checkItem.taskIndex
                    visible: !checkItem.isHeader
                    anchors.left: box.right
                    anchors.leftMargin: 9
                    anchors.right: rightRow.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: checkItem.task ? checkItem.task.text : ""
                    wrapMode: Text.Wrap
                    color: checkItem.task && checkItem.task.done ? root.th.muted : root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    font.strikeout: checkItem.task ? checkItem.task.done : false
                }

                // The done toggle only covers the row before the date and
                // remove controls, so those buttons never mark the task done.
                Item {
                    visible: !checkItem.isHeader
                    anchors.left: parent.left
                    anchors.right: rightRow.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    CardTapHandler {
                        suppressSelection: false
                        acceptedButtons: Qt.LeftButton
                        onAction: {
                            if (!root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                                return;
                            root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y);
                            root.toggle(checkItem.taskIndex);
                        }
                    }
                }

                HoverHandler { id: rowHover
                    enabled: !checkItem.isHeader
                    onHoveredChanged: checkItem.hoveredNow = hovered
                }
                CardTapHandler {
                    enabled: !checkItem.isHeader
                    acceptedButtons: Qt.RightButton
                    onAction: {
                        if (root.canInteractAt(point.scenePosition.x, point.scenePosition.y))
                            root.remove(checkItem.taskIndex);
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

            CardTapHandler {
                acceptedButtons: Qt.LeftButton
                onAction: addField.forceActiveFocus()
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

                CardTapHandler {
                    suppressSelection: false
                    acceptedButtons: Qt.LeftButton
                    onAction: root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y)
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
