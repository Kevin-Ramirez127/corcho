import QtQuick

CardFrame {
    id: root

    property var player: null
    property string errorText: ""

    function poll() {
        try {
            var list = JSON.parse(root.app.mprisPlayers());
            player = list.length > 0 ? list[0] : null;
            errorText = player ? "" : "No media player found. Start one in your session.";
        } catch (e) {
            player = null;
            errorText = "" + e;
        }
    }

    function act(action) {
        if (!player) return;
        root.app.mprisAction(player.playerName, action);
        pollTimer.restart();
    }

    Timer {
        id: pollTimer
        interval: 1800
        repeat: true
        running: root.visible && root.app !== undefined
        onTriggered: root.poll()
    }

    onAppChanged: if (root.app) poll()
    Component.onCompleted: if (root.app) poll()

    Column {
        anchors.fill: parent
        spacing: root.th.space2
        Row {
            width: parent.width
            spacing: root.th.spaceSnug
            Rectangle {
                width: 54
                height: 54
                radius: root.th.radiusControl
                color: root.th.surfaceStrong
                clip: true

                Image {
                    anchors.fill: parent
                    visible: root.player && root.player.artUrl && root.player.artUrl.indexOf("file:") === 0
                    source: root.player && root.player.artUrl ? root.player.artUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !(root.player && root.player.artUrl && root.player.artUrl.indexOf("file:") === 0)
                    name: "music-2"
                    size: root.th.iconLarge
                    color: root.th.muted
                }
            }

            Column {
                width: parent.width - 64
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.th.spaceHalf
                Text {
                    width: parent.width
                    text: root.player ? (root.player.title || "Unknown track") : "Nothing playing"
                    color: root.th.text
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeBody
                    font.weight: root.th.fontWeightMedium
                }
                Text {
                    width: parent.width
                    text: root.player ? (root.player.artist || "") : root.errorText
                    color: root.th.text2
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                Text {
                    width: parent.width
                    visible: root.player && root.player.album
                    text: root.player ? root.player.album : ""
                    color: root.th.muted
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.th.space4
            Icon {
                name: "skip-back"
                size: root.th.iconLarge
                color: root.th.text2
                TapHandler { onTapped: root.act("previous") }
            }
            Icon {
                name: root.player && root.player.status === "Playing" ? "pause" : "play"
                size: root.th.iconLarge
                color: root.th.accent
                TapHandler { onTapped: root.act("play-pause") }
            }
            Icon {
                name: "skip-forward"
                size: root.th.iconLarge
                color: root.th.text2
                TapHandler { onTapped: root.act("next") }
            }
        }
    }
}
