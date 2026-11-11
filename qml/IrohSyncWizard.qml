import QtQuick

Item {
    id: root

    property var app
    property var th
    property bool opened: false
    property string mode: "home" // home | create | join
    property string ticket: ""
    property string shownTicket: ""
    property string errorText: ""

    signal closed()

    anchors.fill: parent
    visible: opened
    z: 640

    readonly property var status: {
        try { return JSON.parse(app.irohJson || "{}"); } catch (e) { return {}; }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.opened
        onTriggered: root.app.refresh()
    }

    function open() {
        mode = "home";
        ticket = "";
        shownTicket = "";
        errorText = "";
        opened = true;
    }

    function close() {
        opened = false;
        root.closed();
    }

    function setSetting(key, value) {
        root.app.setSetting(key, JSON.stringify(value));
    }

    function create() {
        errorText = "";
        var value = root.app.irohCreate();
        if (value === "") {
            errorText = "Could not create the shared workspace.";
            return;
        }
        shownTicket = value;
        setSetting("iroh_sync_enabled", true);
        mode = "create";
    }

    function join() {
        errorText = "";
        if (ticket.trim() === "") {
            errorText = "Paste a ticket first.";
            return;
        }
        var value = root.app.irohJoin(ticket.trim());
        if (value === "") {
            errorText = "Could not join with that ticket.";
            return;
        }
        setSetting("iroh_sync_enabled", true);
        close();
    }

    function showTicket(readOnly) {
        errorText = "";
        var value = root.app.irohShare(readOnly);
        if (value === "") {
            errorText = readOnly ? "No read ticket is available." : "No write ticket is available.";
            return;
        }
        shownTicket = value;
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea {
            anchors.fill: parent
            onClicked: function (mouse) {
                var p = panel.mapFromItem(root, mouse.x, mouse.y);
                if (p.x < 0 || p.y < 0 || p.x > panel.width || p.y > panel.height)
                    root.close();
            }
        }
    }

    Rectangle {
        id: panel
        width: Math.min(640, root.width - 32)
        height: Math.min(560, root.height - 32)
        anchors.centerIn: parent
        radius: root.th.radiusPanel
        color: root.th.menu
        border.width: root.th.borderWidth
        border.color: root.th.border

        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: root.th.space5
            spacing: root.th.space4

            Item {
                width: parent.width
                height: 26
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28
                    text: "Peer sync"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizePage
                    font.weight: root.th.fontWeightMedium
                }
                Icon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: "x"
                    size: root.th.iconBody
                    color: root.th.muted
                    TapHandler { onTapped: root.close() }
                }
            }

            Text {
                width: parent.width
                text: "Corcho can sync this workspace directly between your devices with Iroh. "
                      + "No server or Git remote is required."
                color: root.th.text2
                wrapMode: Text.WordWrap
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
                lineHeight: root.th.lineHeightNormal
            }

            Row {
                width: parent.width
                spacing: root.th.space2
                AppButton {
                    th: root.th
                    text: "Create shared workspace"
                    variant: root.mode === "create" ? "solid" : "ghost"
                    onClicked: root.create()
                }
                AppButton {
                    th: root.th
                    text: "Join with a ticket"
                    variant: root.mode === "join" ? "solid" : "ghost"
                    onClicked: root.mode = "join"
                }
            }

            Column {
                width: parent.width
                spacing: root.th.space2
                visible: root.mode === "join"
                Text {
                    text: "Ticket"
                    color: root.th.text2
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                AppTextField {
                    width: parent.width
                    th: root.th
                    text: root.ticket
                    placeholder: "Paste the ticket from your other device"
                    onEdited: function (value) { root.ticket = value; }
                }
                Row {
                    spacing: root.th.space2
                    AppButton {
                        th: root.th
                        text: "Join"
                        variant: "solid"
                        onClicked: root.join()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: root.th.borderWidth
                visible: root.shownTicket !== ""
                color: root.th.border
            }

            Column {
                width: parent.width
                spacing: root.th.space2
                visible: root.shownTicket !== ""
                Text {
                    width: parent.width
                    text: "Share ticket (treat it like a password)"
                    color: root.th.text2
                    wrapMode: Text.WordWrap
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                TextEdit {
                    width: parent.width
                    height: 72
                    text: root.shownTicket
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    clip: true
                    color: root.th.text
                    font.family: root.th.fontMono
                    font.pixelSize: root.th.fontSizeCaption
                    padding: root.th.space2
                }
                Row {
                    spacing: root.th.space2
                    AppButton {
                        th: root.th
                        text: "Copy"
                        onClicked: root.app.copyText(root.shownTicket)
                    }
                    AppButton {
                        th: root.th
                        text: "Show write ticket"
                        onClicked: root.showTicket(false)
                    }
                    AppButton {
                        th: root.th
                        text: "Show read ticket"
                        onClicked: root.showTicket(true)
                    }
                }
            }

            Text {
                width: parent.width
                text: root.errorText
                visible: root.errorText !== ""
                color: root.th.danger
                wrapMode: Text.WordWrap
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }

            Item { width: 1; height: 1 }

            Text {
                width: parent.width
                text: root.status.lastError
                    ? ("Error: " + root.status.lastError)
                    : (root.status.peers > 0
                        ? (root.status.peers + " peer(s) connected")
                        : (root.status.namespace ? "Waiting for peers" : "Not configured"))
                color: root.status.lastError ? root.th.danger : root.th.muted
                wrapMode: Text.WordWrap
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
            }

            Row {
                anchors.right: parent.right
                spacing: root.th.space2
                AppButton {
                    th: root.th
                    text: "Sync now"
                    enabledButton: root.status.namespace !== null && root.status.namespace !== undefined
                    onClicked: root.app.irohSyncNow()
                }
                AppButton {
                    th: root.th
                    text: "Leave"
                    variant: "danger"
                    enabledButton: root.status.namespace !== null && root.status.namespace !== undefined
                    onClicked: {
                        root.app.irohLeave();
                        root.setSetting("iroh_sync_enabled", false);
                        root.shownTicket = "";
                    }
                }
                AppButton {
                    th: root.th
                    text: "Close"
                    variant: "solid"
                    onClicked: root.close()
                }
            }
        }
    }
}
