import QtQuick

Item {
    id: root

    property var th
    property var options: []
    property string value: ""
    property string placeholder: "Select"

    signal selected(string value)
    focus: true
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.current ? root.current.label : root.placeholder
    Accessible.onPressAction: menu.open()
    Keys.onSpacePressed: menu.open()
    Keys.onReturnPressed: menu.open()
    property bool fieldHovered: false

    implicitWidth: 180
    implicitHeight: 34

    readonly property var current: {
        for (let i = 0; i < options.length; i++)
            if (String(options[i].value) === String(value)) return options[i];
        return null;
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.fieldHovered ? root.th.hover : root.th.input
        border.width: 1
        border.color: (open || root.activeFocus) ? root.th.accent : root.th.border
        Behavior on color { ColorAnimation { duration: 110 } }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 20
            elide: Text.ElideRight
            text: root.current ? root.current.label : root.placeholder
            color: root.current ? root.th.text : root.th.muted
            font.family: root.th.fontFamily
            font.pixelSize: 13
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: 13
            color: root.th.muted
        }
    }

    HoverHandler { id: hover
        onHoveredChanged: root.fieldHovered = hovered
    }

    TapHandler {
        onTapped: menu.open()
    }

    ContextMenu {
        id: menu
        th: root.th
        actions: root.options.map(function (o) {
            return { label: o.label, icon: String(o.value) === String(root.value) ? "check" : "", value: o.value };
        })
        onTriggered: function (index) {
            root.selected(String(root.options[index].value));
        }
    }

    property bool open: menu.visible
}
