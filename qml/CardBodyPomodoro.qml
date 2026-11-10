import QtQuick

CardFrame {
    id: root

    property int workMinutes: (card.workMinutes) || 25
    property int breakMinutes: (card.breakMinutes) || 5
    property string phase: (card.phase) || "work"
    property int remaining: (card.remaining !== undefined) ? card.remaining : workMinutes * 60
    property int sessions: (card.sessions) || 0
    property bool running: false
    // Settings are edited on a small in-card panel so the timer keeps its
    // place and the card does not need a separate dialog.
    property bool editing: false
    property int editWork: workMinutes
    property int editBreak: breakMinutes

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

    function playChime() {
        if (root.app && typeof root.app.pomodoroChime === "function")
            root.app.pomodoroChime();
    }

    function openSettings() {
        editWork = workMinutes;
        editBreak = breakMinutes;
        editing = true;
    }

    function saveSettings() {
        workMinutes = Math.max(1, Math.min(180, Math.round(editWork)));
        breakMinutes = Math.max(1, Math.min(60, Math.round(editBreak)));
        editing = false;
        // When the timer is idle, show the newly selected duration right
        // away. A running timer keeps its current countdown.
        if (!running)
            remaining = (phase === "work" ? workMinutes : breakMinutes) * 60;
        persist();
    }

    function cancelSettings() {
        editing = false;
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
            if (root.remaining > 0)
                root.remaining -= 1;
            if (root.remaining === 0) {
                // The phase just ended: play a short chime, then arm the next
                // phase and wait for the user to start it.
                root.playChime();
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
        spacing: root.th.spaceSnug

        Item {
            width: parent.width
            height: 20

            Text {
                anchors.centerIn: parent
                text: root.phase === "work" ? "Focus" : "Break"
                color: root.th.text2
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
                font.weight: root.th.fontWeightMedium
            }

            Item {
                id: editButton
                objectName: "pomodoroEdit"
                width: 22
                height: 22
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.editing || root.cardHovered ? 1 : 0.55
                Accessible.role: Accessible.Button
                Accessible.name: "Edit focus and break length"

                Rectangle {
                    anchors.fill: parent
                    radius: root.th.radiusControl
                    color: editHover.hovered ? root.th.hover : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: "pencil"
                    size: root.th.iconSmall
                    color: root.th.text2
                }
                HoverHandler { id: editHover }
                CardTapHandler {
                    onAction: root.openSettings()
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.clockText(root.remaining)
            color: root.th.text
            font.family: root.th.fontMono
            font.pixelSize: root.th.fontSizeHuge
            font.weight: root.th.fontWeightMedium
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.th.space2
            Repeater {
                model: Math.max(1, root.sessions)
                delegate: Rectangle {
                    required property int index
                    width: 6
                    height: 6
                    radius: root.th.radiusSmall
                    color: index < root.sessions ? root.th.accent : root.th.surfaceStrong
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.th.space2
            AppButton {
                objectName: "pomodoroStart"
                th: root.th
                icon: root.running ? "pause" : "play"
                text: root.running ? "Pause" : "Start"
                variant: "solid"
                onClicked: root.toggle()
            }
            AppButton {
                objectName: "pomodoroReset"
                th: root.th
                icon: "rotate-ccw"
                text: "Reset"
                onClicked: root.reset()
            }
        }
    }

    Rectangle {
        id: settingsPanel
        objectName: "pomodoroEditPanel"
        anchors.fill: parent
        visible: root.editing
        color: root.th.card
        radius: root.th.radiusControl
        z: 10

        Column {
            anchors.fill: parent
            anchors.margins: 4
            spacing: root.th.space2

            Text {
                text: "Timer length"
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
                font.weight: root.th.fontWeightMedium
            }

            Row {
                width: parent.width
                height: 22
                spacing: root.th.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    text: "Focus"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeMicro
                }
                SliderField {
                    objectName: "pomodoroWorkSlider"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(60, parent.width - 94)
                    th: root.th
                    from: 1
                    to: 120
                    value: root.editWork
                    onMoved: root.editWork = Math.round(value)
                }
                Text {
                    objectName: "pomodoroWorkValue"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    text: Math.round(root.editWork) + "m"
                    color: root.th.text2
                    font.family: root.th.fontMono
                    font.pixelSize: root.th.fontSizeMicro
                }
            }

            Row {
                width: parent.width
                height: 22
                spacing: root.th.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    text: "Break"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeMicro
                }
                SliderField {
                    objectName: "pomodoroBreakSlider"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(60, parent.width - 94)
                    th: root.th
                    from: 1
                    to: 60
                    value: root.editBreak
                    onMoved: root.editBreak = Math.round(value)
                }
                Text {
                    objectName: "pomodoroBreakValue"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    text: Math.round(root.editBreak) + "m"
                    color: root.th.text2
                    font.family: root.th.fontMono
                    font.pixelSize: root.th.fontSizeMicro
                }
            }

            Item { width: 1; height: 2 }

            Row {
                anchors.right: parent.right
                spacing: root.th.space2
                AppButton {
                    objectName: "pomodoroCancel"
                    th: root.th
                    text: "Cancel"
                    onClicked: root.cancelSettings()
                }
                AppButton {
                    objectName: "pomodoroSave"
                    th: root.th
                    text: "Save"
                    variant: "solid"
                    onClicked: root.saveSettings()
                }
            }
        }
    }
}
