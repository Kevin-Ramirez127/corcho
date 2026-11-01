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

    implicitWidth: 40
    implicitHeight: 24
    opacity: enabledSwitch ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.th.accent : root.th.surfaceStrong
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? root.th.accent : (root.checked ? root.th.accent : root.th.border)
        Behavior on color { ColorAnimation { duration: 130 } }
    }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        color: root.checked ? root.th.accentInk : root.th.text2
        Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    }

    TapHandler {
        enabled: root.enabledSwitch
        onTapped: root.toggled(!root.checked)
    }
}
