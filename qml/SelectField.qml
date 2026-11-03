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
