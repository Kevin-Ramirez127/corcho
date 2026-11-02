import QtQuick

Item {
    id: root

    property var app
    property var th
    property bool opened: false
    property int selectedIndex: 0

    signal closed()
    property bool rowHovered: false

    anchors.fill: parent
    visible: opened
    z: 400

    function open() {
        opened = true;
        selectedIndex = 0;
        query.text = "";
        rebuild();
        query.forceActiveFocus();
    }

    function close() {
        opened = false;
        root.closed();
    }

    readonly property var commands: [
        { id: "create-note", label: "Add note", icon: "file-text", keywords: "note card" },
        { id: "create-website", label: "Add website", icon: "globe", keywords: "web embed" },
        { id: "create-bookmark", label: "Add bookmark", icon: "bookmark", keywords: "link" },
        { id: "create-api", label: "Add API data", icon: "database", keywords: "http json" },
        { id: "create-ai", label: "Add AI processor", icon: "cpu", keywords: "ai prompt" },
        { id: "create-fragment", label: "Add fragment", icon: "aperture", keywords: "sensory" },
        { id: "create-script", label: "Add script", icon: "terminal", keywords: "shell" },
        { id: "create-checklist", label: "Add checklist", icon: "list-checks", keywords: "todo tasks" },
        { id: "create-kanban", label: "Add kanban", icon: "kanban", keywords: "board columns" },
        { id: "create-whiteboard", label: "Add whiteboard", icon: "pencil", keywords: "draw" },
        { id: "create-pomodoro", label: "Add pomodoro", icon: "timer", keywords: "timer focus" },
        { id: "create-mpris", label: "Add now playing", icon: "music-2", keywords: "music media" },
        { id: "create-grid", label: "Create grid", icon: "layout-grid", keywords: "new grid" },
        { id: "create-folder", label: "Create folder", icon: "folder-plus", keywords: "new folder" },
        { id: "undo", label: "Undo", icon: "undo-2", keywords: "history" },
        { id: "redo", label: "Redo", icon: "rotate-cw", keywords: "history" },
        { id: "settings", label: "Open settings", icon: "settings", keywords: "preferences" }
    ]

    ListModel { id: results }

    function rebuild() {
        var q = query.text.trim().toLowerCase();
        results.clear();
        var found = 0;

        var grids = [];
        try { grids = JSON.parse(app.gridsJson); } catch (e) {}
        for (var i = 0; i < grids.length && found < 8; i++) {
            if (q === "" || grids[i].name.toLowerCase().indexOf(q) >= 0) {
                results.append({ kind: "grid", id: grids[i].id, gridId: grids[i].id, label: grids[i].name, detail: grids[i].cards.length + " cards", icon: "layout-grid" });
                found++;
            }
        }

        var cards = [];
        try { cards = JSON.parse(app.search(q)); } catch (e) {}
        for (var j = 0; j < cards.length && found < 30; j++) {
            var c = cards[j];
            if (c.type === "card") {
                results.append({ kind: "card", id: c.id, gridId: c.gridId, label: c.label, detail: c.gridName, icon: c.icon || "square" });
                found++;
            }
        }

        for (var k = 0; k < commands.length && found < 50; k++) {
            var cmd = commands[k];
            var hay = cmd.label.toLowerCase() + " " + cmd.keywords;
            if (q === "" || hay.indexOf(q) >= 0) {
                results.append({ kind: "command", id: cmd.id, label: cmd.label, detail: "", icon: cmd.icon });
                found++;
            }
        }

        selectedIndex = found > 0 ? 0 : -1;
        list.positionViewAtBeginning();
    }

    function run(index) {
        if (index < 0 || index >= results.count) return;
        var item = results.get(index);
        if (item.kind === "grid") {
            app.switchGrid(item.gridId);
        } else if (item.kind === "card") {
            app.switchGrid(item.gridId);
        } else if (item.kind === "command") {
            if (item.id === "settings") {
                root.close();
                root.settingsRequested();
                return;
            }
            app.command(item.id);
        }
        root.close();
    }

    signal settingsRequested()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        id: panel
        width: Math.min(680, root.width - 80)
        height: 420
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 96
        radius: 14
        color: root.th.menu
        border.width: 1
        border.color: root.th.border

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            AppTextField {
                id: query
                width: parent.width
                inputHeight: 42
                th: root.th
                placeholder: "Search grids, cards and commands"
                onEdited: root.rebuild()
                onAccepted: root.run(root.selectedIndex)
                onKeyPressed: function (event) {
                    if (event.key === Qt.Key_Down) {
                        root.selectedIndex = Math.min(results.count - 1, root.selectedIndex + 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 54
                clip: true
                spacing: 2
                model: results
                currentIndex: root.selectedIndex

                delegate: Item {
                    id: resultRow
                    required property var modelData
                    required property int index
                    property bool hoveredNow: false

                    width: list.width
                    height: 40

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: index === root.selectedIndex ? root.th.surfaceStrong : (resultRow.hoveredNow ? root.th.hover : "transparent")
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.icon || "square"
                            size: 15
                            color: modelData.kind === "command" ? root.th.text2 : root.th.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 120
                            text: modelData.label
                            color: root.th.text
                            elide: Text.ElideRight
                            font.family: root.th.fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 90
                            text: modelData.detail
                            color: root.th.muted
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            font.family: root.th.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    HoverHandler { id: rowHover
                        onHoveredChanged: resultRow.hoveredNow = hovered
                    }
                    TapHandler {
                        onTapped: {
                            root.selectedIndex = index;
                            root.run(index);
                        }
                    }
                }
            }
        }
    }
}
