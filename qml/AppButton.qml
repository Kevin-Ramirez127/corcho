import QtQuick
import "OverlayState.js" as OverlayState

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
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.text !== "" ? root.text : root.icon
    Accessible.description: root.variant === "solid" ? "Primary action" : ""
    function activateAt(sceneX, sceneY) {
        if (OverlayState.allowsCardAction(root, sceneX, sceneY))
            root.clicked();
    }

    function activate() {
        var scene = root.mapToItem(null, root.width / 2, root.height / 2);
        root.activateAt(scene.x, scene.y);
    }

    function beginCardAction() {
        var card = OverlayState.owningCard(root);
        if (card) card.beginActionPress();
    }

    function endCardAction() {
        var card = OverlayState.owningCard(root);
        if (card) card.endActionPress();
    }

    Accessible.onPressAction: root.activate()
    Keys.onSpacePressed: root.activate()
    Keys.onReturnPressed: root.activate()

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

    // A MouseArea grabs the press exclusively. TapHandlers on overlapping
    // cards could all receive the same tap, so pressing a button on the top
    // card also triggered the button on the card underneath.
    MouseArea {
        anchors.fill: parent
        enabled: root.enabledButton
        onPressed: root.beginCardAction()
        onReleased: root.endCardAction()
        onCanceled: root.endCardAction()
        onClicked: function (mouse) {
            var scene = root.mapToItem(null, mouse.x, mouse.y);
            root.activateAt(scene.x, scene.y);
        }
    }
}
