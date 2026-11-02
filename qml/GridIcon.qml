import QtQuick

Item {
    id: root

    property string icon: "layout-grid"
    property color color: "#d98e5c"
    property int size: 16

    implicitWidth: size
    implicitHeight: size
    readonly property bool custom: icon.indexOf("/") === 0 || icon.indexOf("file:") === 0

    Image {
        id: image
        anchors.fill: parent
        visible: root.custom && status !== Image.Error
        source: root.custom ? (root.icon.indexOf("file:") === 0 ? root.icon : "file://" + root.icon) : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Icon {
        anchors.fill: parent
        visible: !root.custom || image.status === Image.Error
        name: root.custom ? "layout-grid" : root.icon
        size: root.size
        color: root.color
    }
}
