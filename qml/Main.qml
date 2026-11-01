import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Corcho 1.0

ApplicationWindow {
    id: root

    visible: true
    width: 1440
    height: 900
    minimumWidth: 900
    minimumHeight: 600
    title: "Corcho"
    color: "#121214"

    FontLoader { id: fontRegular; source: "qrc:/assets/fonts/inter_regular.ttf" }
    FontLoader { id: fontMedium; source: "qrc:/assets/fonts/inter_medium.ttf" }
    FontLoader { id: fontSemi; source: "qrc:/assets/fonts/inter_semibold.ttf" }

    AppController { id: app }

    function parseJson(text, fallback) {
        try { return JSON.parse(text || ""); } catch (e) { return fallback; }
    }

    readonly property var settings: parseJson(app.settingsJson, {})
    readonly property var grids: parseJson(app.gridsJson, [])
    readonly property var cards: parseJson(app.cardsJson, [])
    readonly property var folders: parseJson(app.foldersJson, [])
    readonly property var themes: parseJson(app.themesJson, [])
    readonly property var fonts: parseJson(app.fontsJson, [])

    readonly property var activeGrid: {
        for (var i = 0; i < grids.length; i++)
            if (grids[i].id === app.activeGridId) return grids[i];
        return null;
    }

    readonly property var themeDef: {
        var id = settings.theme || "corcho";
        if (id === "custom" && settings.customTheme) {
            return {
                id: "custom",
                name: "Custom",
                bg: settings.customTheme.background,
                surface: settings.customTheme.surface,
                accent: settings.customTheme.accent,
                text: settings.customTheme.text,
                light: false
            };
        }
        for (var i = 0; i < themes.length; i++)
            if (themes[i].id === id) return themes[i];
        return themes.length > 0 ? themes[0] : { bg: "#121214", surface: "#1b1b1f", accent: "#e0a48f", text: "#f0eee7" };
    }

    readonly property var th: buildTheme(themeDef)

    function buildTheme(def) {
        var isLight = def.light === true;
        var bg = def.bg || "#121214";
        var surface = def.surface || "#1b1b1f";
        var accent = def.accent || "#e0a48f";
        var text = def.text || "#f0eee7";
        var tc = Qt.color(text);
        var ac = Qt.color(accent);
        var lum = 0.2126 * ac.r + 0.7152 * ac.g + 0.0722 * ac.b;

        var family = "Inter";
        var fid = settings.font || "inter";
        for (var i = 0; i < fonts.length; i++) {
            if (fonts[i].id === fid) {
                family = fonts[i].family || Qt.application.font.family;
                break;
            }
        }

        return {
            isLight: isLight,
            bg: bg,
            sidebar: isLight ? Qt.darker(bg, 1.03) : Qt.lighter(bg, 1.12),
            surface: surface,
            card: isLight ? Qt.darker(surface, 1.02) : Qt.lighter(surface, 1.10),
            surfaceStrong: isLight ? Qt.darker(surface, 1.06) : Qt.lighter(surface, 1.28),
            menu: isLight ? Qt.darker(surface, 1.02) : Qt.lighter(surface, 1.18),
            input: Qt.rgba(tc.r, tc.g, tc.b, isLight ? 0.04 : 0.05),
            hover: Qt.rgba(tc.r, tc.g, tc.b, isLight ? 0.05 : 0.06),
            border: Qt.rgba(tc.r, tc.g, tc.b, isLight ? 0.12 : 0.09),
            borderStrong: Qt.rgba(tc.r, tc.g, tc.b, isLight ? 0.22 : 0.18),
            text: text,
            text2: Qt.rgba(tc.r, tc.g, tc.b, 0.70),
            muted: Qt.rgba(tc.r, tc.g, tc.b, 0.45),
            accent: accent,
            accentInk: lum > 0.55 ? "#171717" : "#f7f4ec",
            danger: "#d97a72",
            success: "#7fae83",
            fontFamily: family
        };
    }

    property bool powerbarOpen: false
    property bool settingsOpen: false
    property string settingsTab: "general"
    property bool onboardingOpen: false
    property bool onboardingDismissed: false
    property bool sidebarCollapsed: false

    property var menuActions: []
    property var menuCard: null
    property var menuGrid: null
    property var menuFolder: null
    property var menuWorld: ({ x: 0, y: 0 })
    property var renameTarget: ({ kind: "", id: "" })

    function openSettings(tab) {
        settingsTab = tab || "general";
        settingsOpen = true;
    }

    function showMenu(px, py, actions) {
        menuActions = actions;
        contextMenu.openAt(px, py);
    }

    function openCreateMenu(px, py, wx, wy) {
        menuWorld = { x: wx, y: wy };
        showMenu(px, py, [
            { label: "Add note", icon: "file-text", action: "create:note" },
            { label: "Add website", icon: "globe", action: "create:website" },
            { label: "Add bookmark", icon: "bookmark", action: "create:bookmark" },
            { label: "Add API data", icon: "database", action: "create:api" },
            { label: "Add AI processor", icon: "cpu", action: "create:ai" },
            { label: "Add fragment", icon: "gem", action: "create:fragment" },
            { label: "Add script", icon: "terminal", action: "create:script" },
            { label: "Add checklist", icon: "list-checks", action: "create:checklist" },
            { label: "Add kanban", icon: "kanban", action: "create:kanban" },
            { label: "Add whiteboard", icon: "pencil", action: "create:whiteboard" },
            { label: "Add pomodoro", icon: "timer", action: "create:pomodoro" },
            { label: "Add now playing", icon: "music-2", action: "create:mpris" },
            { label: "Add grid link", icon: "arrow-right", action: "create:gridlink" },
            { separator: true, label: "" },
            { label: "New grid", icon: "layout-grid", action: "new-grid" },
            { label: "New folder", icon: "folder-plus", action: "new-folder" }
        ]);
    }

    function openCardMenu(card, px, py) {
        menuCard = card;
        var actions = [
            { label: "Duplicate card", icon: "copy", action: "card-duplicate" },
            { label: "Change color", icon: "palette", action: "card-color" },
            { label: card.locked ? "Unlock card" : "Lock card", icon: card.locked ? "unlock" : "lock", action: "card-lock" }
        ];
        if (card.url)
            actions.push({ label: "Open link", icon: "external-link", action: "card-open" });
        actions.push({ separator: true, label: "" });
        for (var i = 0; i < grids.length; i++) {
            if (grids[i].id === app.activeGridId) continue;
            actions.push({ label: "Send to " + grids[i].name, icon: "arrow-right", action: "card-send:" + grids[i].id });
        }
        actions.push({ separator: true, label: "" });
        actions.push({ label: "Delete card", icon: "trash-2", action: "card-delete", danger: true });
        showMenu(px, py, actions);
    }

    function openGridMenu(grid, px, py) {
        menuGrid = grid;
        var actions = [
            { label: "Rename grid", icon: "square-pen", action: "grid-rename" }
        ];
        for (var i = 0; i < folders.length; i++)
            actions.push({ label: "Move to " + folders[i].name, icon: "folder-plus", action: "grid-move:" + folders[i].id });
        actions.push({ label: "Move out of folder", icon: "folder", action: "grid-move:" });
        actions.push({ separator: true, label: "" });
        actions.push({ label: "Delete grid", icon: "trash-2", action: "grid-delete", danger: true });
        showMenu(px, py, actions);
    }

    function openFolderMenu(folder, px, py) {
        menuFolder = folder;
        showMenu(px, py, [
            { label: "Rename folder", icon: "square-pen", action: "folder-rename" },
            { label: "Remove folder, keep grids", icon: "folder", action: "folder-delete-keep" },
            { separator: true, label: "" },
            { label: "Remove folder and grids", icon: "trash-2", action: "folder-delete-all", danger: true }
        ]);
    }

    function menuAction(index) {
        if (index < 0 || index >= menuActions.length) return;
        var action = menuActions[index].action || "";
        var parts = action.split(":");
        var kind = parts[0];
        var arg = parts.length > 1 ? parts.slice(1).join(":") : "";

        if (kind === "create") {
            app.createCard(arg, menuWorld.x, menuWorld.y);
            return;
        }
        if (action === "new-grid") { app.createGrid("New Grid"); return; }
        if (action === "new-folder") { app.createFolder("New Folder"); return; }

        if (kind === "card" && menuCard) {
            if (arg === "duplicate") app.duplicateCard(menuCard.id);
            else if (arg === "color") {
                var colors = ["#e0a48f", "#c9a86a", "#7aa2f7", "#86b78a", "#b48ae0", "#d97a72", "#5aa8a0", "#8d8d97"];
                var at = colors.indexOf(menuCard.color);
                app.updateCard(JSON.stringify({ id: menuCard.id, color: colors[(at + 1) % colors.length] }));
            } else if (arg === "lock") {
                app.updateCard(JSON.stringify({ id: menuCard.id, locked: !menuCard.locked }));
            } else if (arg === "open") {
                app.openExternal(menuCard.url);
            } else if (arg === "delete") {
                app.deleteCard(menuCard.id);
            } else if (action.indexOf("card-send:") === 0) {
                app.sendCardToGrid(menuCard.id, arg);
            }
            return;
        }

        if (kind === "grid" && menuGrid) {
            if (arg === "rename") {
                renameTarget = { kind: "grid", id: menuGrid.id };
                prompt.open("Rename grid", menuGrid.name, "Grid name");
            } else if (arg === "delete") {
                app.deleteGrid(menuGrid.id);
            } else if (action.indexOf("grid-move:") === 0) {
                app.moveGridToFolder(menuGrid.id, arg);
            }
            return;
        }

        if (kind === "folder" && menuFolder) {
            if (arg === "rename") {
                renameTarget = { kind: "folder", id: menuFolder.id };
                prompt.open("Rename folder", menuFolder.name, "Folder name");
            } else if (arg === "delete-keep") {
                app.deleteFolder(menuFolder.id, true);
            } else if (arg === "delete-all") {
                app.deleteFolder(menuFolder.id, false);
            }
        }
    }

    function zoomBy(factor) {
        var next = Math.min(3.0, Math.max(0.2, app.zoom * factor));
        var cx = canvas.width / 2;
        var cy = canvas.height / 2;
        var wx = (cx - app.panX) / app.zoom;
        var wy = (cy - app.panY) / app.zoom;
        app.setView(cx - wx * next, cy - wy * next, next);
        app.saveNow();
    }

    Connections {
        target: app
        function onToast(message) { toastHost.show("info", message); }
        function onNotice(kind, message) { toastHost.show(kind, message); }
        function onSettingsJsonChanged() {
            if (!onboardingDismissed && root.settings && root.settings.onboarding_completed === false && root.visible)
                onboarding.open();
        }
    }

    Component.onCompleted: {
        app.boot();
        onboardingTimer.start();
    }

    Timer {
        id: onboardingTimer
        interval: 250
        onTriggered: {
            if (!onboardingDismissed && root.settings && root.settings.onboarding_completed === false)
                onboarding.open();
        }
    }

    Shortcut { sequences: ["Ctrl+K"]; onActivated: powerbar.open() }
    Shortcut { sequences: ["Ctrl+,"]; onActivated: root.openSettings("general") }
    Shortcut { sequences: ["Ctrl+Z"]; onActivated: app.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; onActivated: app.redo() }
    Shortcut { sequence: "Ctrl+Y"; onActivated: app.redo() }
    Shortcut { sequences: ["Ctrl+0"]; onActivated: root.zoomBy(1.0 / app.zoom) }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (powerbar.opened) powerbar.close();
            else if (settingsDialog.opened) settingsDialog.closed();
            else root.settingsOpen = false;
        }
    }

    Row {
        anchors.fill: parent

        Sidebar {
            id: sidebar
            height: parent.height
            app: app
            th: root.th
            settings: root.settings
            grids: root.grids
            folders: root.folders
            activeGridId: app.activeGridId
            collapsed: root.sidebarCollapsed
            onGridSelected: function (id) { app.switchGrid(id) }
            onNewGridRequested: app.createGrid("New Grid")
            onNewFolderRequested: app.createFolder("New Folder")
            onSettingsRequested: root.openSettings("general")
            onPowerbarRequested: powerbar.open()
            onGridMenuRequested: function (grid, x, y) { root.openGridMenu(grid, x, y) }
            onFolderMenuRequested: function (folder, x, y) { root.openFolderMenu(folder, x, y) }
        }

        Column {
            width: parent.width - sidebar.width
            height: parent.height

            Rectangle {
                id: topbar
                width: parent.width
                height: 54
                color: root.th.bg

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.th.border
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Item {
                        width: 28
                        height: 28
                        visible: root.sidebarCollapsed
                        Icon {
                            anchors.centerIn: parent
                            name: "panel-left"
                            size: 15
                            color: root.th.text2
                        }
                        TapHandler { onTapped: root.sidebarCollapsed = false }
                    }

                    TextInput {
                        id: gridTitle
                        width: Math.max(80, contentWidth + 8)
                        text: root.activeGrid ? root.activeGrid.name : ""
                        color: root.th.text
                        font.family: root.th.fontFamily
                        font.pixelSize: 17
                        font.weight: 500
                        selectionColor: root.th.accent
                        onEditingFinished: {
                            if (root.activeGrid && text.trim() !== "") app.renameGrid(root.activeGrid.id, text.trim());
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.cards.length + (root.cards.length === 1 ? " card" : " cards")
                        color: root.th.muted
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    AppButton {
                        th: root.th
                        icon: "search"
                        text: "Powerbar"
                        onClicked: powerbar.open()
                    }

                    Item { width: 6; height: 1 }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "zoom-out"
                        size: 15
                        color: root.th.text2
                        TapHandler { onTapped: root.zoomBy(0.9) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(app.zoom * 100) + "%"
                        color: root.th.text2
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "zoom-in"
                        size: 15
                        color: root.th.text2
                        TapHandler { onTapped: root.zoomBy(1.1) }
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "maximize"
                        size: 14
                        color: root.th.muted
                        TapHandler { onTapped: root.zoomBy(1.0 / app.zoom) }
                    }

                    Item { width: 6; height: 1 }

                    AppButton {
                        th: root.th
                        icon: "plus"
                        text: "Create"
                        variant: "solid"
                        onClicked: {
                            var p = mapToItem(null, width - 220, height + 6);
                            root.openCreateMenu(p.x, p.y,
                                (canvas.width / 2 - app.panX) / app.zoom,
                                (canvas.height / 2 - app.panY) / app.zoom);
                        }
                    }
                }
            }

            CanvasView {
                id: canvas
                width: parent.width
                height: parent.height - topbar.height - statusbar.height
                app: app
                th: root.th
                settings: root.settings
                cards: root.cards
                onMenuRequested: function (card, x, y) { root.openCardMenu(card, x, y) }
                onBackgroundMenuRequested: function (gx, gy, wx, wy) { root.openCreateMenu(gx, gy, wx, wy) }
                onCreateRequested: function (wx, wy) { app.createCard("note", wx, wy) }
            }

            Rectangle {
                id: statusbar
                width: parent.width
                height: 26
                color: root.th.bg

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: root.th.border
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Double-click to create · Ctrl+K Powerbar · Ctrl+Z Undo"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        text: app.syncing ? "Syncing" : ""
                        color: root.th.accent
                        font.family: root.th.fontFamily
                        font.pixelSize: 10
                    }
                    Text {
                        text: "v" + app.version
                        color: root.th.muted
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    ContextMenu {
        id: contextMenu
        parent: root.contentItem
        th: root.th
        actions: root.menuActions
        onTriggered: function (index) { root.menuAction(index) }
    }

    PromptDialog {
        id: prompt
        parent: root.contentItem
        th: root.th
        onAccepted: function (text) {
            if (text.trim() === "") return;
            if (root.renameTarget.kind === "grid") app.renameGrid(root.renameTarget.id, text.trim());
            else if (root.renameTarget.kind === "folder") app.renameFolder(root.renameTarget.id, text.trim());
        }
        onCancelled: {}
    }

    Powerbar {
        id: powerbar
        app: app
        th: root.th
        onSettingsRequested: root.openSettings("general")
    }

    SettingsDialog {
        id: settingsDialog
        app: app
        th: root.th
        opened: root.settingsOpen
        tab: root.settingsTab
        onClosed: root.settingsOpen = false
    }

    Onboarding {
        id: onboarding
        app: app
        th: root.th
        onStartExploring: {
            root.onboardingDismissed = true;
            onboarding.opened = false;
            app.setSetting("onboarding_completed", "true");
        }
        onOpenBackup: {
            root.onboardingDismissed = true;
            onboarding.opened = false;
            app.setSetting("onboarding_completed", "true");
            root.openSettings("data");
        }
    }

    ToastHost {
        id: toastHost
        th: root.th
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 20
        anchors.bottomMargin: 40
    }
}
