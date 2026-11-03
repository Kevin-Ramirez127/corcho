import QtQuick

Item {
    id: root
    required property var app
    required property var th

    property bool opened: false
    property var items: []

    signal closed()

    anchors.fill: parent
    visible: opened
    z: 360

    function load() {
        try { items = JSON.parse(app.templatesJson()); } catch (e) { items = []; }
    }

    function open() {
        opened = true;
        load();
    }

    function close() {
        opened = false;
        root.closed();
    }

    function dropPositionX() {
        var z = Math.max(0.2, app.zoom);
        return (-app.panX + root.width / 2) / z - 120;
    }

    function dropPositionY() {
        var z = Math.max(0.2, app.zoom);
        return (-app.panY + root.height / 2) / z - 80;
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        height: Math.min(460, parent.height - 48)
        radius: root.th.radiusCard
        color: root.th.card
        border.width: 1
        border.color: root.th.border

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Row {
                width: parent.width
                spacing: 10
                Text {
                    width: parent.width - 44
                    text: "Templates"
                    color: root.th.text
                    font.pixelSize: root.th.fontSizeTitle
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    width: 30
                    height: 30
                    radius: 8
                    color: closeHover.containsMouse ? root.th.hover : "transparent"
                    Icon { anchors.centerIn: parent; name: "x"; size: 16; color: root.th.text2 }
                    MouseArea { id: closeHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.close() }
                }
            }

            Text {
                visible: root.items.length === 0
                width: parent.width
                text: "Select one or more cards, right-click and choose \"Save as template\"."
                color: root.th.text2
                wrapMode: Text.WordWrap
                font.pixelSize: root.th.fontSizeBody
            }

            ListView {
                width: parent.width
                height: parent.height - 84
                clip: true
                spacing: 6
                model: root.items

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 52
                    radius: 9
                    color: rowHover.containsMouse ? root.th.hover : root.th.surface

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 150
                        text: modelData.name
                        elide: Text.ElideRight
                        color: root.th.text
                        font.pixelSize: root.th.fontSizeBody
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Rectangle {
                            width: 66
                            height: 32
                            radius: 7
                            color: insertHover.containsMouse ? root.th.accent : "transparent"
                            border.width: 1
                            border.color: root.th.border
                            Text {
                                anchors.centerIn: parent
                                text: "Insert"
                                color: insertHover.containsMouse ? root.th.accentInk : root.th.text
                                font.pixelSize: root.th.fontSizeSmall
                            }
                            MouseArea {
                                id: insertHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    app.insertTemplate(modelData.id, root.dropPositionX(), root.dropPositionY());
                                    root.close();
                                }
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 7
                            color: deleteHover.containsMouse ? root.th.hover : "transparent"
                            Icon { anchors.centerIn: parent; name: "trash-2"; size: 15; color: root.th.text2 }
                            MouseArea {
                                id: deleteHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    app.deleteTemplate(modelData.id);
                                    root.load();
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }
        }
    }
}
