import QtQuick
import "OverlayState.js" as OverlayState

CardFrame {
    id: root

    property var items: (root.card && root.card.items) ? root.card.items : []
    property bool changed: false
    // Task text being edited inline, and the task currently being dragged to
    // another position inside its own done/undone group.
    property string editingId: ""
    property string dragItemId: ""
    property real dragOffset: 0
    property int dragRow: -1
    property bool dragAfter: false

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
        // Regrouping replaces the list model, which otherwise resets the
        // ListView to the top. Keep the current scroll offset.
        var keepY = list.contentY;
        var next = items.slice();
        next[index] = { id: next[index].id, text: next[index].text, done: !next[index].done };
        items = next;
        persist();
        Qt.callLater(function () {
            list.contentY = Math.min(keepY, Math.max(0, list.contentHeight - list.height));
        });
    }

    function remove(index) {
        if (index < 0 || index >= items.length) return;
        var next = items.slice();
        next.splice(index, 1);
        items = next;
        persist();
    }

    // Replace the list while keeping the scroll offset. Reordering and
    // editing rebuild the grouped row model just like toggling does.
    function replaceItems(next) {
        var keepY = list.contentY;
        items = next;
        persist();
        Qt.callLater(function () {
            list.contentY = Math.min(keepY, Math.max(0, list.contentHeight - list.height));
        });
    }

    function itemIndex(itemId) {
        for (var i = 0; i < items.length; i++)
            if (items[i].id === itemId) return i;
        return -1;
    }

    function beginEdit(itemId) {
        editingId = itemId;
        Qt.callLater(function () {
            var row = null;
            for (var i = 0; i < root.rows.length; i++) {
                if (root.rows[i].item && root.rows[i].item.id === itemId) {
                    row = list.itemAtIndex(i);
                    break;
                }
            }
            if (!row) return;
            var field = findEditField(row);
            if (field) {
                field.forceActiveFocus();
                field.selectAll();
            }
        });
    }

    // The editor is nested in the row delegate; find it so focus can be
    // handed over right after it becomes visible.
    function findEditField(node) {
        if (!node) return null;
        if (node.objectName && String(node.objectName).indexOf("checklistTaskEdit_") === 0)
            return node;
        var kids = node.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findEditField(kids[i]);
            if (found) return found;
        }
        return null;
    }

    function commitEdit(itemId, text) {
        if (editingId !== itemId) return;
        editingId = "";
        var clean = text.trim();
        if (clean === "") return;
        var index = itemIndex(itemId);
        if (index < 0) return;
        if (items[index].text === clean) return;
        var next = items.slice();
        next[index] = { id: next[index].id, text: clean, done: next[index].done };
        replaceItems(next);
    }

    function cancelEdit() {
        editingId = "";
    }

    // Drop order is limited to the dragged task's group: a done task can only
    // move among done tasks, an undone task among undone tasks.
    function scheduleMove(itemIndexValue, targetItemId, after) {
        Qt.callLater(function () {
            root.moveTask(itemIndexValue, targetItemId, after);
        });
    }

    function moveTask(itemIndexValue, targetItemId, after) {
        if (itemIndexValue < 0 || itemIndexValue >= items.length) return false;
        var source = items[itemIndexValue];
        var targetIndex = itemIndex(targetItemId);
        if (targetIndex < 0 || targetIndex === itemIndexValue) return false;
        if (items[targetIndex].done !== source.done) return false;

        var next = items.slice();
        next.splice(itemIndexValue, 1);
        var insertAt = -1;
        for (var i = 0; i < next.length; i++)
            if (next[i].id === targetItemId) { insertAt = i; break; }
        if (insertAt < 0) return false;
        if (after) insertAt += 1;
        next.splice(insertAt, 0, source);
        replaceItems(next);
        return true;
    }

    function dropTargetAt(contentY) {
        var sourceIndex = itemIndex(dragItemId);
        if (sourceIndex < 0) return null;
        var done = items[sourceIndex].done;
        var last = -1;
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (!row.item || row.item.done !== done) continue;
            last = i;
            var delegate = list.itemAtIndex(i);
            if (!delegate) continue;
            if (contentY < delegate.y + delegate.height) {
                return { row: i, after: contentY > delegate.y + delegate.height / 2 };
            }
        }
        // Below the last row of the group: drop after it.
        if (last >= 0) return { row: last, after: true };
        return null;
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
            objectName: "checklistList"
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
                readonly property bool editing: checkItem.task !== null
                    && root.editingId === checkItem.task.id
                readonly property bool dragged: checkItem.task !== null
                    && root.dragItemId === checkItem.task.id

                width: list.width
                height: checkItem.isHeader ? 22 : Math.max(30,
                    Math.max(taskText.implicitHeight,
                             checkItem.editing ? editField.contentHeight : 0) + 8)
                z: checkItem.dragged ? 4 : 0
                opacity: checkItem.dragged ? 0.92 : 1
                transform: Translate { y: checkItem.dragged ? root.dragOffset : 0 }

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
                    Icon {
                        objectName: "checklistDrag_" + checkItem.taskIndex
                        anchors.verticalCenter: parent.verticalCenter
                        name: "grip-vertical"
                        size: root.th.iconSmall
                        color: root.th.muted
                        opacity: checkItem.dragged || checkItem.hoveredNow ? 1 : 0
                        CardTapHandler { onAction: {} }
                        DragHandler {
                            id: reorderDrag
                            target: null
                            xAxis.enabled: false
                            yAxis.enabled: true
                            dragThreshold: 2
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            cursorShape: Qt.SizeVerCursor
                            onActiveChanged: {
                                if (active) {
                                    root.dragItemId = checkItem.task.id;
                                    root.dragOffset = 0;
                                    root.dragRow = -1;
                                    root.dragAfter = false;
                                    return;
                                }
                                // Capture the drop before clearing the drag
                                // state: reordering rebuilds the list model,
                                // which destroys this delegate while the
                                // handler is still running.
                                var sourceIndex = checkItem.taskIndex;
                                var targetId = "";
                                if (root.dragRow >= 0 && root.dragRow < root.rows.length) {
                                    var targetRow = root.rows[root.dragRow];
                                    if (targetRow && targetRow.item)
                                        targetId = targetRow.item.id;
                                }
                                var dropAfter = root.dragAfter;
                                root.dragItemId = "";
                                root.dragOffset = 0;
                                root.dragRow = -1;
                                root.dragAfter = false;
                                if (targetId !== "")
                                    root.scheduleMove(sourceIndex, targetId, dropAfter);
                            }
                            onTranslationChanged: {
                                if (!active) return;
                                root.dragOffset = translation.y;
                                var point = list.mapFromItem(
                                    null,
                                    centroid.scenePosition.x,
                                    centroid.scenePosition.y);
                                var target = root.dropTargetAt(point.y + list.contentY);
                                if (target) {
                                    root.dragRow = target.row;
                                    root.dragAfter = target.after;
                                }
                            }
                        }
                    }
                    Icon {
                        objectName: "checklistEdit_" + checkItem.taskIndex
                        anchors.verticalCenter: parent.verticalCenter
                        name: "pencil"
                        size: root.th.iconSmall
                        color: root.th.muted
                        opacity: checkItem.editing || checkItem.hoveredNow ? 1 : 0
                        CardTapHandler {
                            onAction: root.beginEdit(checkItem.task.id)
                        }
                    }
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
                    opacity: checkItem.editing ? 0 : 1
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

                TextInput {
                    id: editField
                    objectName: "checklistTaskEdit_" + checkItem.taskIndex
                    visible: !checkItem.isHeader && checkItem.editing
                    anchors.left: taskText.left
                    anchors.right: taskText.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.max(20, contentHeight)
                    text: checkItem.task ? checkItem.task.text : ""
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    selectionColor: root.th.accent
                    selectedTextColor: root.th.accentInk
                    wrapMode: TextInput.Wrap
                    selectByMouse: true
                    clip: true
                    onAccepted: root.commitEdit(checkItem.task.id, text)
                    onEditingFinished: root.commitEdit(checkItem.task.id, text)
                    Keys.onReturnPressed: function (event) {
                        root.commitEdit(checkItem.task.id, text);
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: function (event) {
                        root.commitEdit(checkItem.task.id, text);
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: root.cancelEdit()

                    CardTapHandler {
                        suppressSelection: false
                        acceptedButtons: Qt.LeftButton
                        onAction: root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y)
                    }
                }

                // The done toggle only covers the row before the date and
                // remove controls, so those buttons never mark the task done.
                Item {
                    visible: !checkItem.isHeader
                    enabled: !checkItem.editing
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

                // Insertion line shown while a task is dragged to a new slot.
                Rectangle {
                    visible: !checkItem.isHeader && root.dragItemId !== ""
                        && root.dragRow === index
                    x: 4
                    width: Math.max(0, list.width - 8)
                    height: 2
                    radius: 1
                    color: root.th.accent
                    y: root.dragAfter ? parent.height - 1 : -1
                    z: 5
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
