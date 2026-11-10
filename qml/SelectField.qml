import QtQuick

Item {
    id: root

    property var th
    property var options: []
    property string value: ""
    property string placeholder: "Select"

    signal selected(string value)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.current ? root.current.label : root.placeholder
    Accessible.onPressAction: root.openMenu()
    Keys.onSpacePressed: root.openMenu()
    Keys.onReturnPressed: root.openMenu()
    property bool fieldHovered: false

    function openMenu() {
        // The window may not exist yet when the field is created inside a
        // card loader, so attach the popup to the content item when opening.
        var win = root.Window.window;
        if (win && menu.parent !== win.contentItem)
            menu.parent = win.contentItem;
        root.forceActiveFocus();
        menu.openBelow(root);
    }

    implicitWidth: 180
    implicitHeight: root.th.controlHeight

    readonly property var current: {
        for (let i = 0; i < options.length; i++)
            if (String(options[i].value) === String(value)) return options[i];
        return null;
    }

    Rectangle {
        anchors.fill: parent
        radius: root.th.radiusControl
        color: root.fieldHovered ? root.th.hover : root.th.input
        border.width: root.th.borderWidth
        border.color: (open || root.activeFocus) ? root.th.accent : root.th.border
        Behavior on color { ColorAnimation { duration: 110 } }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: root.th.space3
        anchors.rightMargin: root.th.space3
        spacing: root.th.space2
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (root.th && root.th.space5 !== undefined ? root.th.space5 : 24)
            elide: Text.ElideRight
            text: root.current ? root.current.label : root.placeholder
            color: root.current ? root.th.text : root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: root.th.iconBody
            color: root.th.muted
        }
    }

    HoverHandler { id: hover
        onHoveredChanged: root.fieldHovered = hovered
    }

    TapHandler {
        onTapped: root.openMenu()
    }

    ContextMenu {
        id: menu
        objectName: root.objectName !== "" ? root.objectName + "Menu" : ""
        parent: root.Window.window ? root.Window.window.contentItem : null
        th: root.th
        actions: root.options.map(function (o) {
            return {
                label: o.label,
                icon: String(o.value) === String(root.value) ? "check" : "",
                action: String(o.value)
            };
        })
        onTriggered: function (value) {
            root.selected(String(value));
        }
    }

    property bool open: menu.visible
}
