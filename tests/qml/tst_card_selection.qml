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

    QtObject {
        id: fakeApp
        property real panX: 0
        property real panY: 0
        property real zoom: 1
        property string activeGridId: "g1"
        property int viewCalls: 0
        function setView(px, py, z) { panX = px; panY = py; zoom = z; viewCalls += 1; }
        function setViewport(x, y, w, h) {}
        function moveCards(ids, dx, dy) {}
        function saveNow() {}
        function updateCard(json) { return true; }
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
        property real borderWidth: 1
        property real borderWidthFocus: 2
        property real borderWidthStrong: 2
        property real cardHeaderHeight: 36
        property real controlHeight: 32
        property string fontFamily: "sans"
        property real fontSizeBody: 14
        property real fontSizeLarge: 20
        property real fontSizeSmall: 12
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
        property real space6: 24
        property real spaceCompact: 8
        property real spaceHalf: 4
        property real spaceSnug: 10
        property color surface: "#1e1e1e"
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
            loader.item.cards = cards;
            wait(120);
        }

        function noteCard(id, x, y) {
            return { id: id, type: "note", x: x, y: y, width: 220, height: 220,
                     title: id, text: "text of " + id, locked: false };
        }

        function init() {
            testRoot.menuCount = 0;
            loader.item.settings = ({});
            loader.item.cards = [];
            loader.item.setSelection([]);
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

        function test_click_empty_canvas_clears_selection() {
            setCards([noteCard("a", 100, 100)]);
            mouseClick(loader.item, 150, 110);
            wait(60);
            compare(loader.item.selectedIds.length, 1);

            mouseClick(loader.item, 700, 500);
            wait(60);
            compare(loader.item.selectedIds.length, 0);
        }

        function test_whiteboard_canvas_click_selects_card() {
            setCards([{ id: "w", type: "whiteboard", x: 100, y: 100, width: 320, height: 260,
                        title: "board", text: "", strokes: [], penWidth: 3, locked: false }]);
            mouseClick(loader.item, 250, 240);
            wait(60);
            compare(loader.item.selectedIds.length, 1);
            compare(loader.item.selectedIds[0], "w");
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

        function test_long_press_on_empty_canvas_opens_menu() {
            setCards([]);
            mousePress(loader.item, 300, 300);
            wait(900);
            compare(testRoot.menuCount, 1);
            mouseRelease(loader.item, 300, 300);
            wait(60);
        }
    }
}
