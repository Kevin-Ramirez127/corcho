import QtQuick

CardFrame {
    id: root

    property string mode: (card.fragmentMode) || "pop"
    property string accent: (card.accent) || root.th.accent
    property bool controlsVisible: false

    readonly property var modes: {
        var list = [
            { value: "pop", label: "Haptic" },
            { value: "gradient", label: "Nebula" },
            { value: "noise", label: "Spectrum" },
            { value: "object", label: "Artifact" },
            { value: "boson", label: "Boson" },
            { value: "vector", label: "Vector" },
            { value: "calendar", label: "Calendar" }
        ];
        try {
            var s = JSON.parse(root.app.settingsJson);
            if (s.unlockedFragments && s.unlockedFragments.indexOf("hypercube") >= 0)
                list.push({ value: "hypercube", label: "Hypercube" });
        } catch (e) {}
        return list;
    }

    FragmentView {
        anchors.fill: parent
        mode: root.mode
        accent: root.accent
        th: root.th
        app: root.app
        active: root.visible
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        width: 34
        height: 34
        radius: 8
        color: root.th.menu
        border.width: 1
        border.color: root.th.border
        opacity: root.controlsVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Icon {
            anchors.centerIn: parent
            name: "sliders-horizontal"
            size: 15
            color: root.th.text2
        }
        TapHandler {
            onTapped: root.controlsVisible = !root.controlsVisible
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: 40
        radius: 10
        color: root.th.menu
        border.width: 1
        border.color: root.th.border
        visible: root.controlsVisible

        Row {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 6

            SelectField {
                width: parent.width - 132
                height: 28
                th: root.th
                value: root.mode
                options: root.modes
                onSelected: function (value) {
                    root.mode = value;
                    root.commit({ fragmentMode: value, accent: root.accent });
                }
            }

            Repeater {
                model: ["#e0a48f", "#7aa2f7", "#86b78a", "#c9a86a"]

                delegate: Item {
                    required property var modelData
                    width: 22
                    height: 28

                    Rectangle {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        radius: 7
                        color: modelData
                        border.width: root.accent === modelData ? 2 : 0
                        border.color: root.th.text
                    }
                    TapHandler {
                        onTapped: {
                            root.accent = modelData;
                            root.commit({ fragmentMode: root.mode, accent: modelData });
                        }
                    }
                }
            }
        }
    }

    HoverHandler {
        onHoveredChanged: if (hovered) root.controlsVisible = true
    }
}
