import QtQuick
import QtTest

// Regression tests for card selection on the canvas.
//
// The note body is a TextEdit: it consumes mouse presses for caret placement,
// so selection cannot rely only on CardFrame's own tap handler. Clicking the
// text area must still select that card (and deselect the previous one).
Item {
    id: testRoot
    width: 900
    height: 700

    // A tall page so scrolling through it can be observed.
    readonly property string tallPage:
        "data:text/html,<html><body style='height:5000px'>page</body></html>"
    // Last value reported by the page probe; a reload would reset it.
    property string pageProbe: ""

    QtObject {
        id: fakeApp
        property real panX: 0
        property real panY: 0
        property real zoom: 1
        property string activeGridId: "g1"
        property int viewCalls: 0
        property string settingsJson: ""
        property string gridsJson: "[]"
        property string cardsJson: "[]"
        property string calendarJson: "{}"
        function setView(px, py, z) { panX = px; panY = py; zoom = z; viewCalls += 1; }
        function setViewport(x, y, w, h) {}
        function moveCards(ids, dx, dy) {}
        function saveNow() {}
        function updateCard(json) { lastUpdate = json; return true; }
        function adblockCheck(url) { return false; }
        function adblockHosts() { return "[]"; }
        function toast(message) {}
        function openExternal(url) {}
        function search(query) { return "[]"; }
        function switchGrid(id) {}
        function command(id) { return "null"; }
        function aiContext(ids) { return ""; }
        function aiSend(provider, model, prompt, context) { return "stream-1"; }
        property string lastUpdate: ""
    }

    QtObject {
        id: theme
        property color accent: "#d98e5c"
        property color accentButton: "#d98e5c"
        property color accentInk: "#1b1b1b"
        property color bg: "#111111"
        property color card: "#222222"
        property color danger: "#d97a72"
        property color border: "#333333"
        property color borderStrong: "#555555"
        property color hover: "#2a2a2a"
        property color menu: "#1c1c1c"
        property color muted: "#808080"
        property color surfaceStrong: "#2a2a2a"
        property color text: "#e6e6e6"
        property color text2: "#b0b0b0"
        property color input: "#1a1a1a"
        property real borderWidth: 1
        property real borderWidthFocus: 2
        property real borderWidthStrong: 2
        property real cardHeaderHeight: 36
        property real controlHeight: 32
        property string fontFamily: "sans"
        property string fontMono: "monospace"
        property real fontSizeBody: 14
        property real fontSizeLarge: 20
        property real fontSizeSmall: 12
        property real lineHeightNormal: 1.2
        property int fontWeightMedium: 500
        property real gridDotOpacity: 0.4
        property real gridDotSize: 1.4
        property real gridStep: 32
        property int iconBody: 18
        property int iconSmall: 14
        property real fontSizeMicro: 10
        property real motionSlow: 120
        property real opacityEmphasis: 1
        property real opacityNone: 0
        property real radiusCard: 14
        property real radiusControl: 6
        property real radiusDot: 3
        property real radiusHairline: 1
        property real radiusKeycap: 4
        property real radiusLarge: 20
        property real radiusMenu: 8
        property real radiusSmall: 4
        property real space1: 4
        property real space2: 8
        property real space3: 12
        property real space4: 16
        property real space5: 20
        property real space6: 24
        property real spaceCompact: 8
        property real spaceHalf: 4
        property real menuItemHeight: 32
        property real spaceSnug: 10
        property color surface: "#1e1e1e"
        property real launcherMaxWidth: 720
        property real launcherHeight: 520
        property real launcherTopMargin: 80
    }

    property int menuCount: 0

    Loader {
        id: loader
        anchors.fill: parent
        source: Qt.resolvedUrl("../../qml/CanvasView.qml")
        onLoaded: {
            item.app = fakeApp;
            item.th = theme;
            item.settings = ({});
            item.cards = [];
        }
    }

    // Second copy of a website body, standing in for the picture-in-picture
    // window: it is where the canvas copy hands its live page over. It sits
    // outside the test window so it never covers the canvas.
    Loader {
        id: pipBody
        x: 1200
        y: 0
        width: 420
        height: 320
        source: ""
        onLoaded: {
            item.detached = true;
            item.showChrome = false;
            item.app = fakeApp;
            item.th = theme;
        }
    }

    // The launcher is normally an overlay in Main; load it here so its focus
    // and search handling can be exercised without a full app instance.
    Loader {
        id: launcherLoader
        source: Qt.resolvedUrl("../../qml/Launcher.qml")
        onLoaded: {
            item.app = fakeApp;
            item.th = theme;
        }
    }

    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onBackgroundMenuRequested(gx, gy, wx, wy) { testRoot.menuCount += 1; }
    }

    TestCase {
        name: "CardSelection"
        when: windowShown

        function setCards(cards) {
            loader.item.setSelection([]);
            loader.item.floatingIds = [];
            loader.item.cards = cards;
            wait(120);
        }

        function noteCard(id, x, y) {
            return { id: id, type: "note", x: x, y: y, width: 220, height: 220,
                     title: id, text: "text of " + id, locked: false };
        }

        function imageCard(id, x, y) {
            return { id: id, type: "file", x: x, y: y, width: 260, height: 220,
                     title: id, text: "", path: "", fileKind: "image",
                     name: id + ".png", locked: false };
        }

        function init() {
            testRoot.menuCount = 0;
            testRoot.pageProbe = "";
            fakeApp.settingsJson = "";
            if (launcherLoader.item) {
                launcherLoader.item.close();
                launcherLoader.item.opened = false;
            }
            pipBody.source = "";
            loader.item.raiseOrder = [];
            loader.item.settings = ({});
            loader.item.floatingIds = [];
            loader.item.cards = [];
            loader.item.setSelection([]);
            loader.item.pendingFocusCardId = "";
            loader.item.forceActiveFocus();
            wait(60);
        }

        function test_click_header_selects_card() {
            setCards([noteCard("a", 100, 100)]);
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "a");
        }

        // Regression: clicking the note body (the TextEdit) used to focus the
        // editor without selecting the card, leaving the old selection intact.
        function test_click_note_body_selects_card() {
            setCards([noteCard("a", 100, 100), noteCard("b", 400, 100)]);
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.selectedIds[0], "a");

            mouseClick(loader.item, 460, 220);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "b");
        }

        function cardItem(id) {
            var delegate = findChild(loader.item, "cardLoader_" + id);
            return delegate ? delegate.item : null;
        }

        function findCardFrame(node) {
            if (node && node.card !== undefined && node.detached !== undefined)
                return node;
            var children = node ? node.children : [];
            for (var i = 0; i < children.length; i++) {
                var found = findCardFrame(children[i]);
                if (found) return found;
            }
            return null;
        }

        function test_click_does_not_move_other_cards() {
            setCards([
                { id: "img", type: "file", x: 100, y: 100, width: 280, height: 240,
                  title: "img", text: "", path: "/missing.png", fileKind: "image",
                  name: "img.png", locked: false },
                { id: "note", type: "note", x: 140, y: 140, width: 260, height: 220,
                  title: "note", text: "hello", locked: false }
            ]);
            var img = cardItem("img");
            var note = cardItem("note");
            verify(img !== null);
            verify(note !== null);
            var ix = img.x, iy = img.y, nx = note.x, ny = note.y;

            mouseClick(loader.item, 160, 150);
            wait(60);

            compare(img.x, ix);
            compare(img.y, iy);
            compare(note.x, nx);
            compare(note.y, ny);
        }

        // Overlapping cards used to both receive the same tap, so clicking the
        // top card also selected and raised the card underneath it.
        function test_overlapping_cards_select_top_card_only() {
            setCards([imageCard("bottom", 100, 100), imageCard("top", 150, 150)]);
            mouseClick(loader.item, 180, 165);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "top");
            compare(loader.item.raiseOrder.length, 1);
            compare(loader.item.raiseOrder[0], "top");
        }

        function test_overlapping_note_over_image_selects_note() {
            setCards([imageCard("img", 100, 100), noteCard("note", 150, 150)]);
            mouseClick(loader.item, 180, 165);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "note");
            compare(loader.item.raiseOrder.length, 1);
            compare(loader.item.raiseOrder[0], "note");
        }

        function test_click_raises_single_card() {
            setCards([noteCard("a", 100, 100), noteCard("b", 400, 100)]);
            mouseClick(loader.item, 450, 110);
            wait(60);
            compare(loader.item.raiseOrder.length, 1);
            compare(loader.item.raiseOrder[0], "b");
            verify(loader.item.cardStackZ("b") > loader.item.cardStackZ("a"));
        }

        // Clicking one card while a multi-selection is active only narrows the
        // selection; it must not disturb the stacking order.
        function test_click_during_multiselect_does_not_raise() {
            setCards([noteCard("a", 100, 100), noteCard("b", 400, 100)]);
            mouseClick(loader.item, 150, 110);
            mouseClick(loader.item, 450, 110, Qt.LeftButton, Qt.ControlModifier);
            wait(60);
            compare(loader.item.selectedIds.length, 2);

            loader.item.raiseOrder = [];
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.raiseOrder.length, 0);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "a");
        }

        function test_click_empty_canvas_clears_selection() {
            setCards([noteCard("a", 100, 100)]);
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.selectedIds.length, 1);

            mouseClick(loader.item, 700, 500);
            wait(60);
            compare(loader.item.selectedIds.length, 0);
        }

        // A card shown in a picture-in-picture window remains on the canvas as
        // a greyed placeholder whose return action routes back to Main.
        function test_floating_card_shows_return_overlay() {
            setCards([noteCard("a", 100, 100)]);
            loader.item.floatingIds = ["a"];
            wait(60);
            var card = cardItem("a");
            verify(card !== null);
            compare(card.floating, true);
            var shade = findChild(card, "floatingShade");
            verify(shade !== null);
            compare(shade.visible, true);

            var returned = "";
            loader.item.returnCardRequested.connect(function (id) { returned = id; });
            card.returnRequested();
            compare(returned, "a");
        }

        // The detached copy fills its window, and editing it must not rewrite
        // the canvas card's geometry.
        function test_floating_window_keeps_canvas_geometry() {
            var component = Qt.createComponent("../../qml/FloatingCardWindow.qml");
            compare(component.status, Component.Ready);
            var card = noteCard("float", 100, 100);
            var win = component.createObject(null, {
                "app": fakeApp, "th": theme, "cardId": "float", "cardData": card,
                "bodySource": Qt.resolvedUrl("../../qml/CardBodyNote.qml"),
                "gridId": "g1", "initialWidth": 340, "initialHeight": 320
            });
            verify(win !== null);
            wait(120);
            var frame = findCardFrame(win.contentItem);
            verify(frame !== null);
            compare(frame.detached, true);
            compare(frame.showChrome, false);
            compare(frame.surfaceless, true);
            compare(frame.width, win.width);
            compare(frame.height, win.height - win.titleBarHeight);

            frame.commit({}, "changed");
            var saved = JSON.parse(fakeApp.lastUpdate);
            compare(saved.x, 100);
            compare(saved.y, 100);
            compare(saved.width, 220);
            compare(saved.height, 220);
            compare(saved.text, "changed");

            win.close();
            wait(30);
        }

        function test_whiteboard_canvas_click_selects_card() {            setCards([{ id: "w", type: "whiteboard", x: 100, y: 100, width: 320, height: 260,
                        title: "board", text: "", strokes: [], penWidth: 3, locked: false }]);
            mouseClick(loader.item, 250, 240);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "w");
        }

        function test_whiteboard_delete_requires_confirmation() {
            setCards([{ id: "w", type: "whiteboard", x: 100, y: 100, width: 320, height: 260,
                        title: "board", text: "", penWidth: 3, locked: false,
                        strokes: [{ color: "#ffffff", width: 3,
                                    points: [{ x: 10, y: 10 }, { x: 40, y: 40 }] }] }]);
            var board = cardItem("w");
            verify(board !== null);
            compare(board.strokes.length, 1);

            var clearButton = findChild(board, "clearStrokes");
            verify(clearButton !== null);
            mouseClick(clearButton, clearButton.width / 2, clearButton.height / 2);
            wait(60);
            // The content stays until the confirmation action is chosen.
            compare(board.strokes.length, 1);

            var menu = board.clearMenuPopup;
            verify(menu !== null);
            verify(menu.opened);
            menu.activate(0);
            wait(60);
            compare(board.strokes.length, 0);
        }

        // Ctrl-click on a body must be additive just like the header.
        function test_ctrl_click_note_body_adds_to_selection() {
            setCards([noteCard("a", 100, 100), noteCard("b", 400, 100)]);
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.selectedIds[0], "a");

            mouseClick(loader.item, 460, 220, Qt.LeftButton, Qt.ControlModifier);
            wait(60);
            compare(loader.item.selectedIds.length, 2);
            verify(loader.item.selectedIds.indexOf("a") >= 0);
            verify(loader.item.selectedIds.indexOf("b") >= 0);
        }

        function test_ctrl_click_checklist_row_adds_to_selection() {
            setCards([noteCard("a", 100, 100),
                       { id: "check", type: "checklist", x: 400, y: 100, width: 300, height: 260,
                         title: "tasks", text: "", locked: false,
                         items: [{ id: "i1", text: "task one", done: false }] }]);
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.selectedIds[0], "a");

            mouseClick(loader.item, 550, 163, Qt.LeftButton, Qt.ControlModifier);
            wait(60);
            compare(loader.item.selectedIds.length, 2);
            verify(loader.item.selectedIds.indexOf("a") >= 0);
            verify(loader.item.selectedIds.indexOf("check") >= 0);
        }

        function test_checklist_item_click_selects_card() {
            setCards([{ id: "check", type: "checklist", x: 100, y: 100, width: 300, height: 260,
                        title: "tasks", text: "", locked: false,
                        items: [{ id: "i1", text: "task one", done: false }] }]);
            // The first row sits just below the progress bar in the card body.
            mouseClick(loader.item, 250, 163);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "check");
        }

        function checklistBody() {
            var cardLoader = findChild(loader.item, "cardLoader_check");
            verify(cardLoader !== null);
            return cardLoader.item;
        }

        function test_checklist_date_button_does_not_complete_task() {
            setCards([{ id: "check", type: "checklist", x: 100, y: 100, width: 300, height: 260,
                        title: "tasks", text: "", locked: false,
                        items: [{ id: "i1", text: "task one", done: false }] }]);
            var body = checklistBody();
            var dateButton = findChild(body, "checklistDate_0");
            verify(dateButton !== null);

            mouseClick(dateButton, dateButton.width / 2, dateButton.height / 2);
            wait(60);
            compare(body.items.length, 1);
            compare(body.items[0].done, false);
        }

        function test_checklist_remove_button_removes_task() {
            setCards([{ id: "check", type: "checklist", x: 100, y: 100, width: 300, height: 260,
                        title: "tasks", text: "", locked: false,
                        items: [{ id: "i1", text: "task one", done: false }] }]);
            var body = checklistBody();
            var removeButton = findChild(body, "checklistRemove_0");
            verify(removeButton !== null);

            mouseClick(removeButton, removeButton.width / 2, removeButton.height / 2);
            wait(60);
            compare(body.items.length, 0);
        }

        // A long task grows the input instead of scrolling it sideways, and
        // the input carries the same border as every other text field.
        function test_checklist_add_field_wraps_inside_designed_input() {
            setCards([{ id: "check", type: "checklist", x: 100, y: 100, width: 300, height: 260,
                        title: "tasks", text: "", locked: false, items: [] }]);
            var body = checklistBody();
            var add = findChild(body, "checklistAddField");
            var box = findChild(body, "checklistAddBox");
            verify(add !== null);
            verify(box !== null);
            compare(add.wrapMode, TextInput.Wrap);
            verify(box.border.width > 0);

            var initialHeight = box.height;
            add.forceActiveFocus();
            wait(30);
            verify(add.activeFocus);
            add.text = "A long task description that has to wrap onto another line "
                + "instead of running off the right side of the card.";
            wait(80);
            verify(box.height > initialHeight);
        }

        // Long checklist items wrap and make their row taller.
        function test_checklist_item_text_wraps() {
            setCards([{ id: "check", type: "checklist", x: 100, y: 100, width: 300, height: 260,
                        title: "tasks", text: "", locked: false,
                        items: [{ id: "i1", done: false,
                                  text: "A very long checklist task that cannot fit on a single "
                                      + "row and therefore needs to wrap onto more lines." }] }]);
            var label = findChild(checklistBody(), "checklistTaskText_0");
            verify(label !== null);
            compare(label.wrapMode, Text.Wrap);
            verify(label.lineCount > 1);
        }

        // Ctrl+Left/Right at the start/end of a field must not fall through to
        // the canvas arrow-key panning.
        function test_ctrl_arrow_at_text_boundary_does_not_pan_canvas() {
            setCards([noteCard("a", 100, 100)]);
            var editor = findChild(loader.item.bodyItem("a"), "noteEditor");
            verify(editor !== null);
            editor.forceActiveFocus();
            wait(30);

            var before = fakeApp.viewCalls;
            editor.cursorPosition = 0;
            keyClick(editor, Qt.Key_Left, Qt.ControlModifier);
            wait(40);
            compare(fakeApp.viewCalls, before);

            editor.cursorPosition = editor.text.length;
            keyClick(editor, Qt.Key_Right, Qt.ControlModifier);
            wait(40);
            compare(fakeApp.viewCalls, before);
        }

        // Opening the launcher must put the caret in the search field. It used
        // to focus the AppTextField wrapper, so typing did nothing.
        function test_launcher_focuses_search_field() {
            launcherLoader.item.open();
            wait(80);
            var field = findChild(launcherLoader.item, "launcherQuery");
            verify(field !== null);
            verify(field.input.activeFocus);
            launcherLoader.item.close();
            wait(30);
            loader.item.forceActiveFocus();
        }

        // Newly created note and checklist cards expose a focusBody() hook;
        // the canvas uses it to put the caret in the editor right away.
        function test_new_note_and_checklist_bodies_take_focus() {
            setCards([noteCard("new-note", 100, 100)]);
            loader.item.focusCard("new-note");
            tryVerify(function () {
                var editor = findChild(loader.item.bodyItem("new-note"), "noteEditor");
                return editor !== null && editor.activeFocus;
            }, 2000);

            setCards([{ id: "new-check", type: "checklist", x: 100, y: 100,
                        width: 300, height: 260, title: "tasks", text: "",
                        locked: false, items: [] }]);
            loader.item.focusCard("new-check");
            tryVerify(function () {
                var add = findChild(loader.item.bodyItem("new-check"), "checklistAddField");
                return add !== null && add.activeFocus;
            }, 2000);
        }

        // The AI card preset dropdown opens and a click on an option selects
        // that preset on the card.
        function test_ai_preset_dropdown_selects_preset() {
            fakeApp.settingsJson = JSON.stringify({ aiPresets: [
                { id: "p1", name: "Fast", provider: "openai", model: "small" },
                { id: "p2", name: "Deep", provider: "openai", model: "large" }
            ] });
            setCards([{ id: "ai", type: "ai", x: 100, y: 100, width: 340, height: 380,
                        title: "AI", text: "", prompt: "", context: "", lastResult: "",
                        presetId: "", linkedIds: [], locked: false }]);
            var body = loader.item.bodyItem("ai");
            verify(body !== null);
            var select = findChild(body, "aiPresetSelect");
            verify(select !== null);

            var at = select.mapToItem(loader.item, select.width / 2, select.height / 2);
            mouseClick(loader.item, at.x, at.y);
            wait(80);
            var menu = findChild(select, "aiPresetSelectMenu");
            verify(menu !== null);
            verify(menu.visible);

            // First row is "Settings default"; choose the first real preset.
            var win = testRoot.Window.window;
            mouseClick(win.contentItem, menu.x + 30,
                       menu.y + menu.padding + theme.menuItemHeight + theme.spaceHalf + 16);
            wait(80);
            compare(select.value, "p1");
            compare(body.presetId, "p1");
            menu.close();
        }

        function test_click_above_card_does_not_toggle_covered_checklist_task() {
            setCards([{ id: "check", type: "checklist", x: 100, y: 100, width: 300, height: 260,
                        title: "tasks", text: "", locked: false,
                        items: [{ id: "i1", text: "task one", done: false }] },
                       noteCard("top", 100, 100)]);
            var body = checklistBody();
            compare(body.items[0].done, false);

            // This point is over a checklist task row, but the note card is on
            // top of it and must receive the click on its own.
            mouseClick(loader.item, 200, 163);
            wait(60);
            compare(loader.item.selectedIds[0], "top");
            compare(body.items.length, 1);
            compare(body.items[0].done, false);
        }

        function test_kanban_item_click_selects_card() {
            setCards([{ id: "board", type: "kanban", x: 100, y: 100, width: 380, height: 300,
                        title: "board", text: "", locked: false,
                        columns: [{ id: "c1", title: "To do", items: [{ id: "k1", text: "kanban task" }] }] }]);
            mouseClick(loader.item, 290, 183);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "board");
        }

        function test_marquee_selects_multiple_cards() {
            setCards([noteCard("a", 60, 60), noteCard("b", 340, 60)]);
            mousePress(loader.item, 30, 30);
            mouseMove(loader.item, 620, 320);
            mouseMove(loader.item, 640, 330);
            mouseRelease(loader.item, 640, 330);
            wait(80);
            compare(loader.item.selectedIds.length, 2);
        }

        // Dragging one card of a multi-selection must move the rest of the
        // selection live, not only once the pointer is released.
        function test_drag_moves_selection_live() {
            setCards([noteCard("a", 100, 100), noteCard("b", 400, 100)]);
            mouseClick(loader.item, 150, 110);
            mouseClick(loader.item, 450, 110, Qt.LeftButton, Qt.ControlModifier);
            wait(60);
            compare(loader.item.selectedIds.length, 2);

            var bLoader = findChild(loader.item, "cardLoader_b");
            verify(bLoader !== null);
            compare(bLoader.x, 0);
            compare(bLoader.y, 0);

            mousePress(loader.item, 150, 110);
            mouseMove(loader.item, 210, 170);
            mouseMove(loader.item, 230, 190);
            wait(30);

            // The other selected card follows before the drop.
            verify(bLoader.x > 10);
            verify(bLoader.y > 10);

            mouseRelease(loader.item, 230, 190);
            wait(80);

            // Its model position is updated on drop, so the preview resets.
            compare(bLoader.x, 0);
            compare(bLoader.y, 0);
        }

        // Dragging the top card by a spot where the covered card's header
        // lies must only move the top card.
        function test_drag_top_card_does_not_move_covered_card() {
            setCards([noteCard("bottom", 100, 100), noteCard("top", 100, 120)]);
            var bottom = cardItem("bottom");
            var top = cardItem("top");
            verify(bottom !== null);
            verify(top !== null);
            var bx = bottom.x, by = bottom.y;
            var tx = top.x, ty = top.y;

            mousePress(loader.item, 150, 128);
            mouseMove(loader.item, 200, 178);
            mouseMove(loader.item, 210, 188);
            mouseRelease(loader.item, 210, 188);
            wait(80);

            compare(bottom.x, bx);
            compare(bottom.y, by);
            verify(top.x > tx || top.y > ty);
        }

        function test_long_press_on_empty_canvas_opens_menu() {
            setCards([]);
            mousePress(loader.item, 300, 300);
            wait(900);
            compare(testRoot.menuCount, 1);
            mouseRelease(loader.item, 300, 300);
            wait(60);
        }

        function websiteCard(id, x, y, url, w, h) {
            return { id: id, type: "website", x: x, y: y,
                     width: w || 420, height: h || 320,
                     title: id, text: "", url: url || "", locked: false };
        }

        // The visible tooltip of the window, or null. QtTest's findChild only
        // walks the item tree, and a closed ToolTip is not in it at all.
        function findToolTip() {
            var win = testRoot.Window.window;
            if (!win) return null;
            var tip = findChild(win.contentItem, "ToolTip");
            return tip && tip.visible ? tip : null;
        }

        // The popup item carries no text property of its own; the label is a
        // child of it.
        function toolTipText(node) {
            if (!node) return "";
            if (typeof node.text === "string" && node.text.length > 0)
                return node.text;
            var kids = node.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = toolTipText(kids[i]);
                if (found) return found;
            }
            return "";
        }

        function probePage(view, script) {
            testRoot.pageProbe = "";
            view.runJavaScript(script, function (value) {
                testRoot.pageProbe = String(value === undefined || value === null
                    ? "" : value);
            });
        }

        // A website body owns the loaded page, so it has to survive scrolling
        // away; plain cards are still dropped while they are off screen.
        function test_website_body_stays_alive_off_screen() {
            setCards([websiteCard("web", 6000, 6000, "")]);
            verify(loader.item.bodyItem("web") !== null);

            setCards([noteCard("far", 6000, 6000)]);
            verify(loader.item.bodyItem("far") === null);
        }

        // Opening a website card in a picture-in-picture window must move the
        // live page instead of loading the site a second time, and the page
        // has to come back to the canvas untouched.
        function test_website_page_survives_picture_in_picture_handoff() {
            setCards([websiteCard("web", 100, 100, testRoot.tallPage)]);
            var body = loader.item.bodyItem("web");
            verify(body !== null);
            tryVerify(function () { return body.view !== null; }, 8000);
            // loadProgress is a percentage, 0..100.
            tryVerify(function () {
                return body.view && body.view.loadProgress === 100;
            }, 8000);

            var page = body.view;
            probePage(page, "window.__mark = 'alive'; window.scrollTo(0, 600); " +
                            "window.__mark + '|' + window.pageYOffset;");
            tryCompare(testRoot, "pageProbe", "alive|600", 8000);

            // Hand it over exactly like the picture-in-picture window does.
            var handed = loader.item.releaseCardWebView("web");
            verify(handed === page);
            verify(body.view === null);
            // The canvas copy must not open a second copy of the site.
            verify(body.ensureView() === null);
            verify(body.view === null);

            pipBody.source = Qt.resolvedUrl("../../qml/CardBodyWebsite.qml");
            verify(pipBody.item !== null);
            pipBody.item.hostWebView(page);
            pipBody.item.card = websiteCard("web", 100, 100, testRoot.tallPage);

            var host = page.parent, moved = false;
            while (host) {
                if (host === pipBody.item) { moved = true; break; }
                host = host.parent;
            }
            verify(moved, "the page did not move into the second body");
            verify(pipBody.item.view === page);

            wait(300);
            probePage(page, "window.__mark + '|' + window.pageYOffset;");
            tryCompare(testRoot, "pageProbe", "alive|600", 8000);

            // And back to the canvas copy when the window closes.
            var back = pipBody.item.releaseWebView();
            verify(back === page);
            verify(loader.item.acceptCardWebView("web", back));
            var canvasBody = loader.item.bodyItem("web");
            verify(canvasBody.view === page);
            wait(300);
            probePage(page, "window.__mark + '|' + window.pageYOffset;");
            tryCompare(testRoot, "pageProbe", "alive|600", 8000);

            pipBody.source = "";
        }

        // The resize grip must always be covered by the rounded card surface,
        // while staying out of the 16px strip that holds the scrollbars.
        function test_resize_grip_stays_inside_rounded_card() {
            var radii = [0, 14, 20, 28];
            for (var i = 0; i < radii.length; i++) {
                var radius = radii[i];
                fakeApp.settingsJson = JSON.stringify({ card_radius: radius });
                setCards([noteCard("grip", 100, 100)]);
                var card = loader.item.bodyItem("grip");
                verify(card !== null);
                var grip = findChild(card, "resizeGrip");
                verify(grip !== null, "no grip at radius " + radius);

                // The grip icon is rotated by 90 degrees, so map all four
                // corners and work with the axis-aligned bounding box.
                var corners = [[0, 0], [grip.width, 0],
                               [0, grip.height], [grip.width, grip.height]];
                var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
                for (var c = 0; c < corners.length; c++) {
                    var p = grip.mapToItem(card, corners[c][0], corners[c][1]);
                    minX = Math.min(minX, p.x);
                    maxX = Math.max(maxX, p.x);
                    minY = Math.min(minY, p.y);
                    maxY = Math.max(maxY, p.y);
                }
                var w = card.width, h = card.height;
                verify(maxX <= w && maxY <= h, "grip outside the card");
                // Clear of the scrollbar strip, which starts 16px in.
                verify(w - minX <= 16,
                       "grip reaches into the scrollbar strip at radius " + radius);
                // Inside the rounded corner: the point sits on the arc that
                // cuts the corner back by the radius.
                if (radius > 0 && maxX > w - radius && maxY > h - radius) {
                    var dx = maxX - (w - radius);
                    var dy = maxY - (h - radius);
                    verify(dx * dx + dy * dy <= radius * radius,
                           "grip sticks out of the rounded corner at radius " + radius);
                }
            }
            fakeApp.settingsJson = "";
        }

        // Every toolbar button of a website card explains itself on hover.
        function test_website_buttons_show_tooltips() {
            // Wide enough that the zoom buttons (hidden below 500px) exist too.
            setCards([websiteCard("web", 100, 100, "", 640, 320)]);
            var body = loader.item.bodyItem("web");
            verify(body !== null);

            var buttons = ["webBack", "webForward", "webReload", "webZoomOut",
                           "webZoomIn", "webOpenExternal", "webKeepAwake",
                           "webSession"];
            for (var i = 0; i < buttons.length; i++) {
                var button = findChild(body, buttons[i]);
                verify(button !== null, "missing button " + buttons[i]);
                var at = button.mapToItem(loader.item, button.width / 2,
                                          button.height / 2);
                mouseMove(loader.item, at.x, at.y);
                tryVerify(function () { return findToolTip() !== null; }, 3000,
                          "no tooltip for " + buttons[i]);
                verify(toolTipText(findToolTip()).length > 0,
                       "tooltip of " + buttons[i] + " has no text");
                mouseMove(loader.item, 5, 5);
                tryVerify(function () { return findToolTip() === null; }, 3000,
                          "tooltip of " + buttons[i] + " stays after hover");
            }
        }
    }
}
