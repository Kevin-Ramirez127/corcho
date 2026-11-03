import QtQuick

MenuList {
    id: root

    property var actions: []

    signal triggered(string action)

    function openAt(px, py) {
        items = actions;
        areaW = parent ? parent.width : 0;
        areaH = parent ? parent.height : 0;
        showAt(px, py);
    }

    // Opens the menu directly below an item, flipping above it when there is
    // not enough room. Coordinates are mapped into the menu's parent, which
    // consumers should set to the window content item.
    function openBelow(item) {
        items = actions;
        var win = item.Window.window;
        areaW = win ? win.width : 0;
        areaH = win ? win.height : 0;
        var origin = item.mapToItem(parent, 0, 0);
        var menuH = estimatedHeight();
        var py = origin.y + item.height + 2;
        if (areaH > 0 && py + menuH > areaH - 4)
            py = origin.y - menuH - 2;
        showAt(origin.x, py);
    }

    onChosen: function (action) { root.triggered(action); }
}
