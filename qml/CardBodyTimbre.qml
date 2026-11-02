import QtQuick

CardFrame {
    id: root

    property real volume: (card.volume !== undefined) ? card.volume : 0.35
    property real toneFreq: (card.toneFreq !== undefined) ? card.toneFreq : 220
    property real toneMix: (card.toneMix !== undefined) ? card.toneMix : 0.4
    property bool running: false
    property real tick: 0

    readonly property bool reducedMotion: {
        try { return JSON.parse(root.app.settingsJson).reduced_motion === true; }
        catch (e) { return false; }
    }

    function pushAudio() {
        if (root.running)
            root.app.timbreStart(root.card.id, root.volume, root.toneFreq, root.toneMix);
    }

    function persist() {
        root.commit({
            volume: root.volume,
            toneFreq: root.toneFreq,
            toneMix: root.toneMix
        });
    }

    function toggle() {
        if (root.running) {
            root.running = false;
            root.app.timbreStop(root.card.id);
        } else {
            root.running = true;
            pushAudio();
        }
    }

    Component.onDestruction: root.app.timbreStop(root.card.id)
    onRunningChanged: canvas.requestPaint()

    Timer {
        id: persistTimer
        interval: 260
        repeat: false
        onTriggered: root.persist()
    }

    Timer {
        interval: 33
        repeat: true
        running: root.running && root.visible && !root.reducedMotion
        onTriggered: {
            root.tick += 0.033;
            canvas.requestPaint();
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 2
        spacing: root.th.space2
        Row {
            width: parent.width
            height: 30
            spacing: root.th.spaceCompact
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "audio-lines"
                size: root.th.iconSmall
                color: root.th.text2
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 96
                text: "Timbre"
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
                font.weight: root.th.fontWeightMedium
            }
            AppButton {
                anchors.verticalCenter: parent.verticalCenter
                th: root.th
                icon: root.running ? "pause" : "play"
                text: root.running ? "Stop" : "Start"
                variant: root.running ? "ghost" : "solid"
                onClicked: root.toggle()
            }
        }

        Canvas {
            id: canvas
            width: parent.width
            height: 56

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var a = root.th.accent;
                var bars = 34;
                var bw = width / bars;
                for (var b = 0; b < bars; b++) {
                    var n = Math.sin(root.tick * 6 + b * 0.7) * 0.5 + Math.sin(root.tick * 13 + b * 1.9) * 0.3;
                    var v = root.running ? Math.abs(n) * 0.5 + 0.06 : 0.05;
                    var bh = v * height * 0.9;
                    ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.18 + v * 0.7);
                    ctx.fillRect(b * bw + bw * 0.24, height / 2 - bh / 2, bw * 0.52, bh);
                }
                ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.35);
                ctx.fillRect(0, height / 2 - 0.5, width, 1);
            }
        }

        Row {
            width: parent.width
            height: 22
            spacing: root.th.space2
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                text: "Volume"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
            }
            SliderField {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                th: root.th
                from: 0
                to: 100
                value: root.volume * 100
                onMoved: {
                    root.volume = value / 100;
                    root.pushAudio();
                    persistTimer.restart();
                }
            }
        }

        Row {
            width: parent.width
            height: 22
            spacing: root.th.space2
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                text: "Tone"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
            }
            SliderField {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                th: root.th
                from: 80
                to: 880
                value: root.toneFreq
                onMoved: {
                    root.toneFreq = value;
                    root.pushAudio();
                    persistTimer.restart();
                }
            }
        }

        Row {
            width: parent.width
            height: 22
            spacing: root.th.space2
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                text: "Mix"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
            }
            SliderField {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                th: root.th
                from: 0
                to: 100
                value: root.toneMix * 100
                onMoved: {
                    root.toneMix = value / 100;
                    root.pushAudio();
                    persistTimer.restart();
                }
            }
        }
    }
}
