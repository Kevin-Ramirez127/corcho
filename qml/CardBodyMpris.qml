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
        running: root.visible
        onTriggered: root.poll()
    }

    Component.onCompleted: poll()

    Column {
        anchors.fill: parent
        spacing: 8

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: 54
                height: 54
                radius: 8
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
                    size: 22
                    color: root.th.muted
                }
            }

            Column {
                width: parent.width - 64
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.player ? (root.player.title || "Unknown track") : "Nothing playing"
                    color: root.th.text
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: 13
                    font.weight: 500
                }
                Text {
                    width: parent.width
                    text: root.player ? (root.player.artist || "") : root.errorText
                    color: root.th.text2
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    visible: root.player && root.player.album
                    text: root.player ? root.player.album : ""
                    color: root.th.muted
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            Icon {
                name: "skip-back"
                size: 18
                color: root.th.text2
                TapHandler { onTapped: root.act("previous") }
            }
            Icon {
                name: root.player && root.player.status === "Playing" ? "pause" : "play"
                size: 24
                color: root.th.accent
                TapHandler { onTapped: root.act("play-pause") }
            }
            Icon {
                name: "skip-forward"
                size: 18
                color: root.th.text2
                TapHandler { onTapped: root.act("next") }
            }
        }
    }
}
