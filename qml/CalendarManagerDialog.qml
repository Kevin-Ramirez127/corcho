import QtQuick

Item {
    id: root

    property var th
    property var app
    property bool opened: false

    readonly property var calendars: {
        try { return (JSON.parse(root.app.calendarJson).calendars || []); }
        catch (e) { return []; }
    }
    readonly property var themePalette: ["#d98e5c", "#7aa2f7", "#86b78a", "#c9a86a", "#d97a72", "#8d8d97"]

    signal closed()

    anchors.fill: parent
    visible: opened
    z: 620

    function open() {
        opened = true;
        nameField.input.text = "";
    }

    function close() {
        opened = false;
        root.closed();
    }

    function nextColor() {
        return palette[calendars.length % palette.length];
    }

    function create() {
        var name = nameField.input.text.trim();
        if (name === "") return;
        root.app.createCalendar(name, nextColor());
        nameField.input.text = "";
    }

    function cycleColor(calendar) {
        var at = palette.indexOf(calendar.color);
        var color = palette[(at + 1) % palette.length];
        root.app.updateCalendar(calendar.id, "", color);
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        width: Math.min(520, root.width - 32)
        height: Math.min(520, root.height - 32)
        anchors.centerIn: parent
        radius: root.th.radiusCard
        color: root.th.menu
        border.width: root.th.borderWidth
        border.color: root.th.border

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: root.th.spaceSnug
            Row {
                width: parent.width
                height: 24

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24
                    text: "Calendars"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSubtitle
                    font.weight: root.th.fontWeightMedium
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "x"
                    size: root.th.iconBody
                    color: root.th.muted
                    TapHandler { onTapped: root.close() }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 116
                clip: true
                spacing: root.th.space1
                model: root.calendars

                delegate: Item {
                    id: row
                    required property var modelData
                    property bool deleteArmed: false

                    width: list.width
                    height: 38

                    Rectangle {
                        anchors.fill: parent
                        radius: root.th.radiusControl
                        color: rowHover.hovered ? root.th.hover : "transparent"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: root.th.radiusLoose
                        color: row.modelData.color || root.th.accent
                        border.width: root.th.borderWidth
                        border.color: root.th.border
                        TapHandler { onTapped: root.cycleColor(row.modelData) }
                    }

                    AppTextField {
                        anchors.left: parent.left
                        anchors.leftMargin: 26
                        anchors.right: parent.right
                        anchors.rightMargin: 82
                        anchors.verticalCenter: parent.verticalCenter
                        th: root.th
                        inputHeight: 30
                        text: row.modelData.name
                        onCommitted: function (value) {
                            if (value.trim() !== "" && value.trim() !== row.modelData.name)
                                root.app.updateCalendar(row.modelData.id, value.trim(), "");
                        }
                    }

                    AppButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        th: root.th
                        text: row.deleteArmed ? "Confirm" : "Delete"
                        variant: "danger"
                        enabledButton: root.calendars.length > 1
                        onClicked: {
                            if (row.deleteArmed) root.app.deleteCalendar(row.modelData.id);
                            else row.deleteArmed = true;
                        }
                    }

                    Timer {
                        interval: 3000
                        running: row.deleteArmed
                        onTriggered: row.deleteArmed = false
                    }

                    HoverHandler { id: rowHover }
                }
            }

            Row {
                width: parent.width
                height: 34
                spacing: root.th.space2
                AppTextField {
                    id: nameField
                    width: parent.width - 70
                    th: root.th
                    inputHeight: 32
                    placeholder: "New calendar"
                    onAccepted: root.create()
                }
                AppButton {
                    th: root.th
                    text: "Add"
                    variant: "solid"
                    onClicked: root.create()
                }
            }

            Text {
                text: "Dates linked to a deleted calendar are removed."
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
            }
        }
    }
}
