import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string name: "square"
    property color color: "#f0eee7"
    property int size: 18
    property real stroke: 1.5

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Image {
        id: source
        anchors.fill: parent
        source: "qrc:/assets/icons/" + root.name + ".svg"
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: source
        colorization: 1.0
        colorizationColor: root.color
        smooth: true
    }
}
