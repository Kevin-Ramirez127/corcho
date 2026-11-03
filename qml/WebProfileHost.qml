import QtQuick
import QtWebEngine

Item {
    id: root

    property var profile: null

    width: 0
    height: 0

    WebEngineProfilePrototype {
        id: sharedPrototype
        storageName: "corcho-sites"
    }

    Component.onCompleted: profile = sharedPrototype.instance()
}
