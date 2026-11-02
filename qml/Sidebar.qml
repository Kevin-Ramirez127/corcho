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
    signal toggleCollapsed()
    signal gridMenuRequested(var grid, real x, real y)
    signal folderMenuRequested(var folder, real x, real y)

    implicitWidth: collapsed ? root.th.sidebarCollapsedWidth : root.th.sidebarWidth


    Rectangle {
        anchors.fill: parent
        color: root.th.sidebar

        Rectangle {
            anchors.right: parent.right
            width: root.th.borderWidth
            height: parent.height
            color: root.th.border
        }
    }

    Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.th.space4
        spacing: root.th.space2
        Item {
            width: parent.width
            height: root.th.sidebarHeaderHeight

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.th.space2
                visible: !root.collapsed

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "pin"
                    size: root.th.iconLarge
                    color: root.th.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Corcho"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeTitle
                    font.weight: root.th.fontWeightMedium
                }
            }

            Item {
                visible: root.collapsed
                anchors.centerIn: parent
                width: 24
                height: 24
                Icon {
                    anchors.centerIn: parent
                    name: "pin"
                    size: root.th.iconLarge
                    color: root.th.accent
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.th.space2
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
        anchors.bottomMargin: root.th.space4
        spacing: root.th.space1
        Item {
            width: parent.width
            height: root.th.statusbarHeight

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.th.space2
                visible: !root.collapsed

                Rectangle {
                    width: 8
                    height: 8
                    radius: root.th.radiusMicro
                    color: root.app.syncing ? root.th.accent : (root.settings && root.settings.cloud_sync_enabled ? root.th.success : root.th.muted)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.app.syncing ? "Syncing" : (root.settings && root.settings.cloud_sync_enabled ? "Cloud sync on" : "Local only")
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
            }
        }

        Item {
            width: parent.width
            height: root.th.controlHeight

            AppButton {
                anchors.left: parent.left
                anchors.leftMargin: root.collapsed ? 4 : 12
                anchors.verticalCenter: parent.verticalCenter
                th: root.th
                icon: "settings"
                text: root.collapsed ? "" : "Settings"
                onClicked: root.settingsRequested()
                width: root.collapsed ? 28 : parent.width - 60
            }

            Item {
                anchors.right: parent.right
                anchors.rightMargin: root.collapsed ? 4 : 12
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                Accessible.role: Accessible.Button
                Accessible.name: root.collapsed ? "Expand sidebar" : "Collapse sidebar"

                Icon {
                    anchors.centerIn: parent
                    name: "panel-left"
                    size: root.th.iconSmall
                    color: root.th.text2
                }
                TapHandler { onTapped: root.toggleCollapsed() }
            }
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
            spacing: root.th.spaceHalf
            Repeater {
                model: root.folders

                delegate: Column {
                    required property var modelData
                    width: listColumn.width

                    Item {
                        width: parent.width
                        height: root.th.menuItemHeight

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.th.space2
                            visible: !root.collapsed

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.collapsed ? "chevron-right" : "chevron-down"
                                size: root.th.iconBody
                                color: root.th.muted
                            }
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "folder-plus"
                                size: root.th.iconBody
                                color: root.th.text2
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: root.th.text2
                                font.family: root.th.fontFamily
                                font.pixelSize: root.th.fontSizeSmall
                                font.weight: root.th.fontWeightMedium
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
            height: root.th.controlHeight

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: root.th.space2
                anchors.rightMargin: root.th.space2
                radius: root.th.radiusControl
                color: root.activeGridId === modelData.id ? root.th.surfaceStrong : (row.hoveredNow ? root.th.hover : "transparent")
            }

            Row {
                x: root.collapsed ? (row.width - width) / 2 : 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.th.space2
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "layout-grid"
                    size: root.th.iconBody
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
                    font.pixelSize: root.th.fontSizeBody
                    font.weight: root.activeGridId === modelData.id ? 500 : 400
                }
                Text {
                    visible: !root.collapsed
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.cards.length
                    color: root.th.muted
                    font.family: root.th.fontMono
                    font.pixelSize: root.th.fontSizeSmall
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
