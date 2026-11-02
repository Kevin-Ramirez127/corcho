import QtQuick
import "IconData.js" as IconData

Item {
    id: root

    property string name: "square"
    property color color: "#d98e5c"
    property int size: 18
    property real stroke: 1.5

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    readonly property string sourceUrl: {
        var c = root.color;
        function hex(v) {
            var s = Math.round(Math.max(0, Math.min(255, v * 255))).toString(16);
            return s.length < 2 ? "0" + s : s;
        }
        return IconData.source(root.name, "#" + hex(c.r) + hex(c.g) + hex(c.b));
    }

    Image {
        anchors.fill: parent
        source: root.sourceUrl
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
