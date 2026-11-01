import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var th
    property real from: 0
    property real to: 100
    property real value: 0
    property string suffix: ""

    signal moved(real value)

    implicitWidth: 200
    implicitHeight: 24

    Slider {
        id: slider
        anchors.fill: parent
        from: root.from
        to: root.to
        value: root.value
        stepSize: 1
        onMoved: root.moved(value)

        background: Rectangle {
            x: 0
            y: (parent.height - height) / 2
            width: parent.width
            height: 4
            radius: 2
            color: root.th.surfaceStrong
        }

        handle: Rectangle {
            x: slider.visualPosition * (slider.availableWidth - width)
            y: (slider.availableHeight - height) / 2
            width: 14
            height: 14
            radius: 7
            color: root.th.text
            border.width: 2
            border.color: root.th.accent
        }
    }
}
