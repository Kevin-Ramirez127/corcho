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

    onChosen: function (action) { root.triggered(action); }
}
