import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Dialogs
import Corcho 1.0

ApplicationWindow {
    id: root

    visible: true
    width: 1440
    height: 900
    minimumWidth: 900
    minimumHeight: 600
    title: "Corcho"
    color: root.th.bg

    FontLoader { id: fontRegular; source: "qrc:/assets/fonts/inter_regular.ttf" }
    FontLoader { id: fontMedium; source: "qrc:/assets/fonts/inter_medium.ttf" }
    FontLoader { id: fontSemi; source: "qrc:/assets/fonts/inter_semibold.ttf" }
    FontLoader { id: fontBrand; source: "qrc:/assets/fonts/texgyreadventor-bold.otf" }

    AppController { id: app }

    function parseJson(text, fallback) {
        try { return JSON.parse(text || ""); } catch (e) { return fallback; }
    }

    function filePath(url) {
        var s = url.toString();
        if (s.indexOf("file://") === 0) s = s.substring(7);
        return decodeURIComponent(s);
    }

    readonly property var settings: parseJson(app.settingsJson, {})
    readonly property var grids: parseJson(app.gridsJson, [])
    readonly property var cards: parseJson(app.cardsJson, [])
    readonly property var allCards: parseJson(app.allCardsJson, [])
    readonly property var folders: parseJson(app.foldersJson, [])
    readonly property var themes: parseJson(app.themesJson, [])
    readonly property var fonts: parseJson(app.fontsJson, [])

    readonly property var activeGrid: {
        for (var i = 0; i < grids.length; i++)
            if (grids[i].id === app.activeGridId) return grids[i];
        return null;
    }

    readonly property bool systemDark: Application.styleHints.colorScheme !== Qt.Light
    readonly property var th: parseJson(appearance.tokensJson, {})

    AppearanceController { id: appearance }

    function refreshAppearance() {
        appearance.refresh(app.settingsJson, app.themesJson, app.fontsJson, systemDark);
    }

    onSystemDarkChanged: refreshAppearance()

    property bool launcherOpen: false
    property bool settingsOpen: false
    property string settingsTab: "general"
    property bool onboardingOpen: false
    property bool onboardingDismissed: false
    property bool sidebarCollapsed: false

    property var menuActions: []
    property var menuCard: null
    property string promptKind: ""
    property var templateTarget: []
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
            { label: "Add card", icon: "plus", children: [
                { label: "Text", icon: "file-text", children: [
                    { label: "Note", icon: "file-text", action: "create:note" },
                    { label: "Checklist", icon: "list-checks", action: "create:checklist" },
                    { label: "Kanban", icon: "kanban", action: "create:kanban" },
                    { label: "Whiteboard", icon: "pencil", action: "create:whiteboard" }
                ] },
                { label: "Web", icon: "globe", children: [
                    { label: "Website", icon: "globe", action: "create:website" },
                    { label: "Bookmark", icon: "bookmark", action: "create:bookmark" },
                    { label: "API data", icon: "database", action: "create:api" },
                    { label: "Grid portal", icon: "arrow-right", action: "create:portal" }
                ] },
                { label: "Media & files", icon: "folder", children: [
                    { label: "File", icon: "file-text", action: "pick-file" },
                    { label: "Folder", icon: "folder-plus", action: "pick-folder" },
                    { label: "Timbre", icon: "audio-lines", action: "create:timbre" },
                    { label: "Now playing", icon: "music-2", action: "create:mpris" }
                ] },
                { label: "Tools", icon: "cpu", children: [
                    { label: "AI node", icon: "cpu", action: "create:ai" },
                    { label: "Script", icon: "terminal", action: "create:script" },
                    { label: "Calendar", icon: "calendar", action: "create:calendar" },
                    { label: "Pomodoro", icon: "timer", action: "create:pomodoro" },
                    { label: "Git repository", icon: "git-branch", action: "create:git" }
                ] }
            ] },
            { separator: true, label: "" },
            { label: "New grid", icon: "layout-grid", action: "new-grid" },
            { label: "New folder", icon: "folder-plus", action: "new-folder" },
            { label: "Templates", icon: "layout-template", action: "templates" }
        ]);
    }

    function openCardMenu(card, px, py) {
        menuCard = card;
        var actions = [
            { label: "Duplicate card", icon: "copy", action: "card:duplicate" },
            { label: "Pin colour", icon: "palette", action: "card:color" },
            { label: "Link date", icon: "calendar", action: "card:link-date" },
            { label: card.locked ? "Unpin card" : "Pin card", icon: card.locked ? "pin-off" : "pin", action: "card:lock" }
        ];
        if (canvas.selectedIds.length > 1)
            actions.push({ label: "Create group", icon: "group", action: "card:group" });
        if (card.group)
            actions.push({ label: "Ungroup", icon: "ungroup", action: "card:ungroup" });
        if (card.syncId) {
            actions.push({ label: "Stop syncing", icon: "unlink", action: "card:unsync" });
        } else {
            var syncTargets = [];
            for (var t = 0; t < allCards.length; t++) {
                var other = allCards[t];
                if (other.id === card.id || other.type !== card.type) continue;
                syncTargets.push({
                    label: (other.title || other.type) + " · " + (other.gridName || "grid"),
                    icon: "link",
                    action: "card:sync:" + other.id
                });
            }
            if (syncTargets.length > 0)
                actions.push({ label: "Sync with card", icon: "link", children: syncTargets });
        }
        actions.push({ label: "Save as template", icon: "layout-template", action: "card:template" });
        if (card.url)
            actions.push({ label: "Open link", icon: "external-link", action: "card:open" });
        actions.push({ separator: true, label: "" });
        var sendTargets = [];
        for (var i = 0; i < grids.length; i++) {
            if (grids[i].id === app.activeGridId) continue;
            sendTargets.push({ label: grids[i].name, icon: "arrow-right", action: "card:send:" + grids[i].id });
        }
        if (sendTargets.length > 0)
            actions.push({ label: "Send to grid", icon: "arrow-right", children: sendTargets });
        actions.push({ separator: true, label: "" });
        actions.push({ label: "Delete card", icon: "trash-2", action: "card:delete", danger: true });
        showMenu(px, py, actions);
    }

    function openGridMenu(grid, px, py) {
        menuGrid = grid;
        var actions = [
            { label: "Rename grid", icon: "square-pen", action: "grid:rename" },
            { label: "Choose icon…", icon: "image", action: "grid:icon" },
            { label: "Use default icon", icon: "layout-grid", action: "grid:icon-reset" }
        ];
        for (var i = 0; i < folders.length; i++)
            actions.push({ label: "Move to " + folders[i].name, icon: "folder-plus", action: "grid:move:" + folders[i].id });
        actions.push({ label: "Move out of folder", icon: "folder", action: "grid:move:" });
        actions.push({ separator: true, label: "" });
        actions.push({ label: "Delete grid", icon: "trash-2", action: "grid:delete", danger: true });
        showMenu(px, py, actions);
    }

    function openFolderMenu(folder, px, py) {
        menuFolder = folder;
        showMenu(px, py, [
            { label: "Rename folder", icon: "square-pen", action: "folder:rename" },
            { label: "Remove folder, keep grids", icon: "folder", action: "folder:delete-keep" },
            { separator: true, label: "" },
            { label: "Remove folder and grids", icon: "trash-2", action: "folder:delete-all", danger: true }
        ]);
    }

    function runMenuAction(action) {
        var parts = action.split(":");
        var kind = parts[0];
        var arg = parts.length > 1 ? parts.slice(1).join(":") : "";

        if (kind === "create") {
            app.createCard(arg, menuWorld.x, menuWorld.y);
            return;
        }
        if (action === "new-grid") { app.createGrid("New Grid"); return; }
        if (action === "new-folder") { app.createFolder("New Folder"); return; }
        if (action === "pick-file") { pinFileDialog.open(); return; }
        if (action === "pick-folder") { pinFolderDialog.open(); return; }
        if (action === "templates") { templatesDialog.open(); return; }

        if (kind === "card" && menuCard) {
            if (arg === "duplicate") app.duplicateCard(menuCard.id);
            else if (arg === "color") {
                var colors = ["#d98e5c", "#c9a86a", "#7aa2f7", "#86b78a", "#5aa8a0", "#d97a72", "#8d8d97"];
                var at = colors.indexOf(menuCard.color);
                app.updateCard(JSON.stringify({ id: menuCard.id, color: colors[(at + 1) % colors.length] }));
            } else if (arg === "link-date") {
                dateLinkDialog.openFor(menuCard.id, "", "", "");
            } else if (arg === "lock") {
                app.updateCard(JSON.stringify({ id: menuCard.id, locked: !menuCard.locked }));
            } else if (arg === "group") {
                app.setCardGroup(JSON.stringify(canvas.selectedIds), "g" + Date.now());
            } else if (arg === "ungroup") {
                app.setCardGroup(JSON.stringify([menuCard.id]), "");
            } else if (arg === "unsync") {
                app.unsyncCard(menuCard.id);
            } else if (arg.indexOf("sync:") === 0) {
                if (!app.syncCards(menuCard.id, arg.slice(5)))
                    toastHost.show("error", "Cards must be the same type");
            } else if (arg === "template") {
                root.templateTarget = canvas.selectedIds.length > 0 ? canvas.selectedIds.slice() : [menuCard.id];
                root.promptKind = "template";
                prompt.open("Save as template", "", "Template name");
            } else if (arg === "open") {
                app.openExternal(menuCard.url);
            } else if (arg === "delete") {
                app.deleteCard(menuCard.id);
            } else if (arg.indexOf("send:") === 0) {
                app.sendCardToGrid(menuCard.id, arg.slice(5));
            }
            return;
        }

        if (kind === "grid" && menuGrid) {
            if (arg === "rename") {
                renameTarget = { kind: "grid", id: menuGrid.id };
                prompt.open("Rename grid", menuGrid.name, "Grid name");
            } else if (arg === "icon") {
                gridIconDialog.open();
            } else if (arg === "icon-reset") {
                app.setGridIcon(menuGrid.id, "layout-grid");
            } else if (arg === "delete") {
                app.deleteGrid(menuGrid.id);
            } else if (arg.indexOf("move:") === 0) {
                app.moveGridToFolder(menuGrid.id, arg.slice(5));
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
            root.refreshAppearance();
            if (!onboardingDismissed && root.settings && root.settings.onboarding_completed === false && root.visible)
                onboarding.open();
        }
        function onThemesJsonChanged() { root.refreshAppearance() }
        function onFontsJsonChanged() { root.refreshAppearance() }
    }

    Component.onCompleted: {
        app.boot();
        root.refreshAppearance();
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

    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: app.reloadIfChanged()
    }

    Shortcut { sequences: ["Ctrl+K"]; onActivated: launcher.open() }
    Shortcut { sequences: ["Ctrl+,"]; onActivated: root.openSettings("general") }
    Shortcut { sequences: ["Ctrl+Z"]; onActivated: app.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; onActivated: app.redo() }
    Shortcut { sequence: "Ctrl+Y"; onActivated: app.redo() }
    Shortcut { sequences: ["Ctrl+0"]; onActivated: root.zoomBy(1.0 / app.zoom) }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (gitWizard.opened) gitWizard.close();
            else if (dateLinkDialog.opened) dateLinkDialog.close();
            else if (calendarManager.opened) calendarManager.close();
            else if (prompt.opened) prompt.close();
            else if (contextMenu.visible) contextMenu.close();
            else if (launcher.opened) launcher.close();
            else if (settingsDialog.opened) settingsDialog.closed();
            else if (onboarding.opened) {
                root.onboardingDismissed = true;
                onboarding.opened = false;
                app.setSetting("onboarding_completed", "true");
            } else root.settingsOpen = false;
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
            collapsed: root.sidebarCollapsed || root.width < 800
            onGridSelected: function (id) { app.switchGrid(id) }
            onNewGridRequested: app.createGrid("New Grid")
            onNewFolderRequested: app.createFolder("New Folder")
            onSettingsRequested: root.openSettings("general")
            onToggleCollapsed: root.sidebarCollapsed = !root.sidebarCollapsed
            onGridMenuRequested: function (grid, x, y) { root.openGridMenu(grid, x, y) }
            onFolderMenuRequested: function (folder, x, y) { root.openFolderMenu(folder, x, y) }
        }

        Column {
            width: parent.width - sidebar.width
            height: parent.height

            Rectangle {
                id: topbar
                width: parent.width
                height: root.th.topbarHeight
                color: root.th.bg

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: root.th.borderWidth
                    color: root.th.border
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: root.th.space5
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.th.space3
                    TextInput {
                        id: gridTitle
                        width: Math.min(360, Math.max(80, contentWidth + 8))
                        text: root.activeGrid ? root.activeGrid.name : ""
                        color: root.th.text
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizePage
                        font.weight: root.th.fontWeightMedium
                        selectionColor: root.th.accent
                        onEditingFinished: {
                            if (root.activeGrid && text.trim() !== "") app.renameGrid(root.activeGrid.id, text.trim());
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.width > 860
                        text: root.cards.length + (root.cards.length === 1 ? " card" : " cards")
                        color: root.th.muted
                        font.family: root.th.fontMono
                        font.pixelSize: root.th.fontSizeSmall
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: root.th.space5
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.th.space2
                    AppButton {
                        th: root.th
                        icon: "search"
                        text: root.width > 1180 ? "Launcher" : ""
                        onClicked: launcher.open()
                    }

                    Item { width: 6; height: 1; visible: root.width > 980 }

                    Icon {
                        visible: root.width > 980
                        anchors.verticalCenter: parent.verticalCenter
                        name: "zoom-out"
                        size: root.th.iconBody
                        color: root.th.text2
                        TapHandler { onTapped: root.zoomBy(0.9) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.width > 980
                        text: Math.round(app.zoom * 100) + "%"
                        color: root.th.text2
                        font.family: root.th.fontMono
                        font.pixelSize: root.th.fontSizeSmall
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.width > 980
                        name: "zoom-in"
                        size: root.th.iconBody
                        color: root.th.text2
                        TapHandler { onTapped: root.zoomBy(1.1) }
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.width > 980
                        name: "maximize"
                        size: root.th.iconBody
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
                onDateLinkRequested: function (cardId, itemId, linkId, date) {
                    dateLinkDialog.openFor(cardId, itemId, linkId, date);
                }
                onCalendarManagerRequested: calendarManager.open()
                onBackgroundMenuRequested: function (gx, gy, wx, wy) { root.openCreateMenu(gx, gy, wx, wy) }
                onCreateRequested: function (wx, wy) { app.createCard("note", wx, wy) }
            }

            Rectangle {
                id: statusbar
                width: parent.width
                height: root.th.statusbarHeight
                color: root.th.bg

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: root.th.borderWidth
                    color: root.th.border
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: root.th.space5
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.th.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Double-click to create"
                        color: root.th.muted
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeSmall
                    }
                    Keycap { th: root.th; text: "Ctrl K" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Launcher"
                        color: root.th.muted
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeSmall
                    }
                    Keycap { th: root.th; text: "Ctrl Z" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Undo"
                        color: root.th.muted
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeSmall
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: root.th.space5
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.th.spaceSnug
                    Text {
                        text: app.syncing ? "Syncing" : ""
                        color: root.th.text2
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeSmall
                    }
                    Text {
                        text: "v" + app.version
                        color: root.th.muted
                        font.family: root.th.fontMono
                        font.pixelSize: root.th.fontSizeSmall
                    }
                }
            }
        }
    }

    FileDialog {
        id: pinFileDialog
        title: "Pin an image, PDF or Markdown file"
        nameFilters: [
            "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.svg)",
            "PDF (*.pdf)",
            "Markdown (*.md *.markdown)"
        ]
        onAccepted: {
            var result = String(app.pinPath(root.filePath(selectedFile), menuWorld.x, menuWorld.y, ""));
            if (result.indexOf("error:") === 0) app.toast(result.slice(6));
        }
    }

    FolderDialog {
        id: pinFolderDialog
        title: "Pin a folder"
        onAccepted: {
            var result = String(app.pinPath(root.filePath(selectedFolder), menuWorld.x, menuWorld.y, ""));
            if (result.indexOf("error:") === 0) app.toast(result.slice(6));
        }
    }

    FileDialog {
        id: gridIconDialog
        title: "Choose a grid icon"
        nameFilters: ["SVG images (*.svg)"]
        onAccepted: if (menuGrid) app.setGridIcon(menuGrid.id, root.filePath(selectedFile))
    }

    ContextMenu {
        id: contextMenu
        parent: root.contentItem
        th: root.th
        actions: root.menuActions
        onTriggered: function (action) { root.runMenuAction(action) }
    }

    PromptDialog {
        id: prompt
        parent: root.contentItem
        th: root.th
        onAccepted: function (text) {
            if (text.trim() === "") return;
            if (root.promptKind === "template") {
                var raw = String(app.createTemplate(text.trim(), JSON.stringify(root.templateTarget)));
                root.promptKind = "";
                if (raw.indexOf("error:") === 0) toastHost.show("error", raw.slice(6));
                return;
            }
            if (root.renameTarget.kind === "grid") app.renameGrid(root.renameTarget.id, text.trim());
            else if (root.renameTarget.kind === "folder") app.renameFolder(root.renameTarget.id, text.trim());
        }
        onCancelled: {}
    }

    DateLinkDialog {
        id: dateLinkDialog
        parent: root.contentItem
        th: root.th
        app: app
    }

    CalendarManagerDialog {
        id: calendarManager
        parent: root.contentItem
        th: root.th
        app: app
    }

    Launcher {
        id: launcher
        app: app
        th: root.th
        onSettingsRequested: root.openSettings("general")
    }

    GitSyncWizard {
        id: gitWizard
        app: app
        th: root.th
    }

    TemplatesDialog {
        id: templatesDialog
        parent: root.contentItem
        app: app
        th: root.th
    }

    SettingsDialog {
        id: settingsDialog
        app: app
        th: root.th
        opened: root.settingsOpen
        tab: root.settingsTab
        onClosed: root.settingsOpen = false
        onGitWizardRequested: gitWizard.open()
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
