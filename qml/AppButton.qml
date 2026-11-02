import QtQuick

Item {
    id: root

    property string text: ""
    property string icon: ""
    property var th
    property string variant: "ghost" // ghost | solid | quiet | danger
    property bool selected: false
    property bool enabledButton: true
    property bool isHovered: false

    signal clicked()
    focus: true
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.text !== "" ? root.text : root.icon
    Accessible.description: root.variant === "solid" ? "Primary action" : ""
    Accessible.onPressAction: root.clicked()
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()

    implicitHeight: root.th.controlHeight
    implicitWidth: Math.max(root.th.controlHeight, row.implicitWidth + root.th.space6)
    opacity: enabledButton ? 1.0 : 0.45

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.th.radiusControl
        color: {
            if (root.variant === "solid") return root.isHovered ? Qt.lighter(root.th.accentButton, 1.06) : root.th.accentButton;
            if (root.variant === "danger") return root.isHovered ? Qt.rgba(0.86, 0.36, 0.36, 0.16) : "transparent";
            if (root.selected) return root.th.surfaceStrong;
            return root.isHovered ? root.th.hover : "transparent";
        }
        border.width: root.activeFocus ? root.th.borderWidthFocus : (root.variant === "ghost" || root.variant === "quiet" ? root.th.borderWidth : 0)
        border.color: root.activeFocus ? root.th.accent : root.th.border
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.th.space2
        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: root.th.iconBody
            color: root.variant === "solid" ? root.th.accentInk : (root.variant === "danger" ? root.th.danger : root.th.text2)
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: root.variant === "solid" ? root.th.accentInk : (root.variant === "danger" ? root.th.danger : root.th.text)
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
        font.weight: root.th.fontWeightMedium
        }
    }

    HoverHandler { id: hover
        onHoveredChanged: root.isHovered = hovered
    }

    TapHandler {
        enabled: root.enabledButton
        onTapped: root.clicked()
    }
}
