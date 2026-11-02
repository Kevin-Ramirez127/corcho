import QtQuick

Item {
    id: root

    property var th
    property bool checked: false
    property bool enabledSwitch: true

    signal toggled(bool value)
    property string accessibleName: ""
    focus: true
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.onPressAction: root.toggled(!root.checked)
    Keys.onSpacePressed: root.toggled(!root.checked)

    implicitWidth: root.th.switchWidth
    implicitHeight: root.th.switchHeight
    opacity: enabledSwitch ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.th.accent : root.th.surfaceStrong
        border.width: root.activeFocus ? root.th.borderWidthFocus : root.th.borderWidth
        border.color: root.activeFocus ? root.th.accent : (root.checked ? root.th.accent : root.th.border)
        Behavior on color { ColorAnimation { duration: 130 } }
    }

    Rectangle {
        width: root.th.switchThumb
        height: root.th.switchThumb
        radius: root.th.radiusBadge
        y: root.th.borderWidth
        x: root.checked ? root.width - width - root.th.borderWidth : root.th.borderWidth
        color: root.checked ? root.th.accentInk : root.th.text2
        Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    }

    TapHandler {
        enabled: root.enabledSwitch
        onTapped: root.toggled(!root.checked)
    }
}
