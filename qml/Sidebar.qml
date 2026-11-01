import QtQuick

Item {
    id: root

    property var app
    property var th
    property var settings
    property var grids: []
    property var folders: []
    property string activeGridId: ""
    property bool collapsed: false
    property bool gridHovered: false

    signal gridSelected(string id)
    signal newGridRequested()
    signal newFolderRequested()
    signal settingsRequested()
    signal powerbarRequested()
    signal gridMenuRequested(var grid, real x, real y)
    signal folderMenuRequested(var folder, real x, real y)

    implicitWidth: collapsed ? 64 : 248

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        color: root.th.sidebar

        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: root.th.border
        }
    }

    Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 16
        spacing: 8

        Item {
            width: parent.width
            height: 40

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                visible: !root.collapsed

                Rectangle {
                    width: 22
                    height: 22
                    radius: 6
                    color: root.th.accent
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 2
                        color: root.th.accentInk
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Corcho"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: 14
                    font.weight: 500
                }
            }

            Item {
                visible: root.collapsed
                anchors.centerIn: parent
                width: 22
                height: 22
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: root.th.accent
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 2
                    color: root.th.accentInk
                }
            }

            Item {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                visible: !root.collapsed

                Icon {
                    anchors.centerIn: parent
                    name: "panel-left"
                    size: 15
                    color: root.th.muted
                }
                TapHandler { onTapped: root.collapsed = true }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            visible: !root.collapsed

            AppButton {
                th: root.th
                icon: "plus"
                text: "Grid"
                onClicked: root.newGridRequested()
            }
            AppButton {
                th: root.th
                icon: "folder-plus"
                text: "Folder"
                onClicked: root.newFolderRequested()
            }
        }
    }

    Column {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: 12
        spacing: 4

        Item {
            width: parent.width
            height: 30

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: !root.collapsed

                Rectangle {
                    width: 7
                    height: 7
                    radius: 4
                    color: root.app.syncing ? root.th.accent : (root.settings && root.settings.cloud_sync_enabled ? root.th.success : root.th.muted)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.app.syncing ? "Syncing" : (root.settings && root.settings.cloud_sync_enabled ? "Cloud sync on" : "Local only")
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        AppButton {
            anchors.left: parent.left
            anchors.leftMargin: root.collapsed ? 16 : 12
            th: root.th
            icon: "search"
            text: root.collapsed ? "" : "Powerbar"
            onClicked: root.powerbarRequested()
            width: root.collapsed ? 32 : 224
        }
        AppButton {
            anchors.left: parent.left
            anchors.leftMargin: root.collapsed ? 16 : 12
            th: root.th
            icon: "settings"
            text: root.collapsed ? "" : "Settings"
            onClicked: root.settingsRequested()
            width: root.collapsed ? 32 : 224
        }
        AppButton {
            anchors.left: parent.left
            anchors.leftMargin: root.collapsed ? 16 : 12
            th: root.th
            icon: "panel-left"
            text: root.collapsed ? "" : "Expand"
            visible: root.collapsed
            onClicked: root.collapsed = false
            width: 32
        }
    }

    Flickable {
        id: list
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        clip: true
        contentHeight: listColumn.height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: listColumn
            width: list.width
            spacing: 2

            Repeater {
                model: root.folders

                delegate: Column {
                    required property var modelData
                    width: listColumn.width

                    Item {
                        width: parent.width
                        height: 30

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: !root.collapsed

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.collapsed ? "chevron-right" : "chevron-down"
                                size: 11
                                color: root.th.muted
                            }
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "folder-plus"
                                size: 13
                                color: root.th.text2
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: root.th.text2
                                font.family: root.th.fontFamily
                                font.pixelSize: 11
                                font.weight: 500
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: root.app.toggleFolder(modelData.id)
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                var p = mapToItem(null, width - 20, height);
                                root.folderMenuRequested(modelData, p.x, p.y);
                            }
                        }
                    }

                    Repeater {
                        model: root.grids.filter(function (g) { return g.folderId === modelData.id; })
                        delegate: gridRow
                    }
                }
            }

            Repeater {
                model: root.grids.filter(function (g) { return !g.folderId; })
                delegate: gridRow
            }
        }
    }

    Component {
        id: gridRow

        Item {
            id: row
            required property var modelData
            property bool hoveredNow: false

            width: listColumn.width
            height: 34

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                radius: 7
                color: root.activeGridId === modelData.id ? root.th.surfaceStrong : (row.hoveredNow ? root.th.hover : "transparent")
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: root.collapsed ? (row.width - 32) / 2 : 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "layout-grid"
                    size: 14
                    color: root.activeGridId === modelData.id ? root.th.accent : root.th.text2
                }
                Text {
                    visible: !root.collapsed
                    anchors.verticalCenter: parent.verticalCenter
                    width: row.width - 100
                    text: modelData.name
                    color: root.activeGridId === modelData.id ? root.th.text : root.th.text2
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: 13
                    font.weight: root.activeGridId === modelData.id ? 500 : 400
                }
                Text {
                    visible: !root.collapsed
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.cards.length
                    color: root.th.muted
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }
            }

            HoverHandler {
                onHoveredChanged: row.hoveredNow = hovered
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.gridSelected(row.modelData.id)
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    var p = mapToItem(null, row.width - 20, row.height);
                    root.gridMenuRequested(row.modelData, p.x, p.y);
                }
            }
        }
    }
}
