import QtQuick

CardFrame {
    id: root

    property int workMinutes: (card.workMinutes) || 25
    property int breakMinutes: (card.breakMinutes) || 5
    property string phase: (card.phase) || "work"
    property int remaining: (card.remaining !== undefined) ? card.remaining : workMinutes * 60
    property int sessions: (card.sessions) || 0
    property bool running: false

    function persist() {
        root.commit({
            workMinutes: root.workMinutes,
            breakMinutes: root.breakMinutes,
            phase: root.phase,
            remaining: root.remaining,
            sessions: root.sessions
        });
    }

    function toggle() {
        running = !running;
        if (!running) persist();
    }

    function reset() {
        running = false;
        phase = "work";
        remaining = workMinutes * 60;
        persist();
    }

    function clockText(seconds) {
        var m = Math.floor(seconds / 60);
        var s = seconds % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            if (root.remaining > 0) {
                root.remaining -= 1;
            } else {
                if (root.phase === "work") {
                    root.sessions += 1;
                    root.phase = "break";
                    root.remaining = root.breakMinutes * 60;
                } else {
                    root.phase = "work";
                    root.remaining = root.workMinutes * 60;
                }
                root.running = false;
                root.persist();
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.phase === "work" ? "Focus" : "Break"
            color: root.th.text2
            font.family: root.th.fontFamily
            font.pixelSize: 11
            font.weight: 500
            font.letterSpacing: 0.6
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.clockText(root.remaining)
            color: root.th.text
            font.family: "JetBrains Mono"
            font.pixelSize: 40
            font.weight: 500
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: Math.max(1, root.sessions)
                delegate: Rectangle {
                    required property int index
                    width: 6
                    height: 6
                    radius: 3
                    color: index < root.sessions ? root.th.accent : root.th.surfaceStrong
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            AppButton {
                th: root.th
                icon: root.running ? "pause" : "play"
                text: root.running ? "Pause" : "Start"
                variant: "solid"
                onClicked: root.toggle()
            }
            AppButton {
                th: root.th
                icon: "rotate-ccw"
                text: "Reset"
                onClicked: root.reset()
            }
        }
    }
}
