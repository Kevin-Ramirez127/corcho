import QtQuick

Item {
    id: root

    property var th
    property var app
    property bool opened: false

    property string sourceCardId: ""
    property string sourceItemId: ""
    property string linkId: ""
    property string titleText: ""
    property string selectedDate: ""
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property var selectedCalendarIds: []
    property string errorText: ""

    readonly property var calendars: {
        try { return (JSON.parse(root.app.calendarJson).calendars || []); }
        catch (e) { return []; }
    }
    readonly property string todayKey: keyFor(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())

    signal closed()

    anchors.fill: parent
    visible: opened
    z: 620

    function keyFor(y, m, d) {
        var mm = m + 1;
        return y + "-" + (mm < 10 ? "0" : "") + mm + "-" + (d < 10 ? "0" : "") + d;
    }

    function fromKey(key) {
        var p = key.split("-");
        if (p.length !== 3) return new Date();
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    }

    function openFor(cardId, itemId, editLinkId, defaultDate, defaultCalendars) {
        sourceCardId = cardId || "";
        sourceItemId = itemId || "";
        linkId = editLinkId || "";
        titleText = "";
        errorText = "";
        selectedCalendarIds = [];

        var data = {};
        try { data = JSON.parse(root.app.calendarJson); } catch (e) { data = {}; }
        var links = data.dateLinks || [];
        var link = null;
        for (var i = 0; i < links.length; i++)
            if (links[i].id === linkId) { link = links[i]; break; }

        if (link) {
            titleText = link.title || "";
            selectedDate = link.date;
            selectedCalendarIds = (link.calendarIds || []).slice();
        } else {
            selectedDate = defaultDate || todayKey;
            var available = calendars;
            if (defaultCalendars && defaultCalendars.length > 0)
                selectedCalendarIds = defaultCalendars.slice();
            else if (available.length > 0)
                selectedCalendarIds = [available[0].id];
        }
        var d = fromKey(selectedDate);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
        titleField.input.text = titleText;
        opened = true;
        titleField.input.forceActiveFocus();
        titleField.input.selectAll();
    }

    function close() {
        opened = false;
        root.closed();
    }

    function toggleCalendar(id) {
        var next = selectedCalendarIds.slice();
        var at = next.indexOf(id);
        if (at >= 0) next.splice(at, 1);
        else next.push(id);
        selectedCalendarIds = next;
    }

    function save() {
        errorText = "";
        var title = titleField.input.text.trim();
        if (selectedCalendarIds.length === 0) {
            errorText = "Choose at least one calendar.";
            return;
        }
        if (sourceCardId === "" && title === "") {
            errorText = "Add a title for this reminder.";
            return;
        }
        var ids = JSON.stringify(selectedCalendarIds);
        if (linkId !== "") {
            root.app.updateDateLink(linkId, selectedDate, ids, title);
        } else {
            var result = String(root.app.addDateLink(sourceCardId, sourceItemId, selectedDate, ids, title));
            if (result.indexOf("error:") === 0) {
                errorText = result.slice(6);
                return;
            }
        }
        close();
    }

    function remove() {
        if (linkId !== "") root.app.deleteDateLink(linkId);
        close();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
       width: Math.min(560, root.width - 32)
        height: Math.min(560, root.height - 32)
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
                height: 26
                spacing: root.th.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 32
                    text: root.linkId === "" ? "Link a date" : "Edit date"
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

            AppTextField {
                id: titleField
                width: parent.width
                th: root.th
                placeholder: "What is happening?"
                onAccepted: root.save()
            }

            Row {
                width: parent.width
                height: 24
                spacing: root.th.space1
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-left"
                    size: root.th.iconSmall
                    color: root.th.text2
                    TapHandler {
                        onTapped: {
                            var d = new Date(root.viewYear, root.viewMonth - 1, 1);
                            root.viewYear = d.getFullYear();
                            root.viewMonth = d.getMonth();
                        }
                    }
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-right"
                    size: root.th.iconSmall
                    color: root.th.text2
                    TapHandler {
                        onTapped: {
                            var d = new Date(root.viewYear, root.viewMonth + 1, 1);
                            root.viewYear = d.getFullYear();
                            root.viewMonth = d.getMonth();
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: new Date(root.viewYear, root.viewMonth, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    color: root.th.text2
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeCaption
                    font.weight: root.th.fontWeightMedium
                }
            }

            CalendarGrid {
                width: parent.width
                height: Math.min(230, parent.height * 0.44)
                th: root.th
                year: root.viewYear
                month: root.viewMonth
                selectedDate: root.selectedDate
                todayDate: root.todayKey
                marks: ({})
                onDateSelected: function (date) { root.selectedDate = date; }
            }

            Text {
                text: "Calendars"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
                font.weight: root.th.fontWeightMedium
            }

            Flow {
                width: parent.width
                height: childrenRect.height
                spacing: root.th.spaceTight
                Repeater {
                    model: root.calendars

                    delegate: Rectangle {
                        required property var modelData
                        height: 24
                        width: chipLabel.width + 26
                        radius: root.th.radiusCard
                        color: root.selectedCalendarIds.indexOf(modelData.id) >= 0 ? root.th.hover : "transparent"
                        border.width: root.th.borderWidth
                        border.color: root.selectedCalendarIds.indexOf(modelData.id) >= 0 ? root.th.accent : root.th.border

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: modelData.color || root.th.accent
                        }
                        Text {
                            id: chipLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 19
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: root.th.text2
                            font.family: root.th.fontFamily
                            font.pixelSize: root.th.fontSizeCaption
                        }
                        TapHandler { onTapped: root.toggleCalendar(modelData.id) }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.errorText
                visible: root.errorText !== ""
                color: root.th.danger
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: 1 }

            Row {
                anchors.right: parent.right
                spacing: root.th.space2
                AppButton {
                    th: root.th
                    text: "Delete"
                    variant: "danger"
                    visible: root.linkId !== ""
                    onClicked: root.remove()
                }
                AppButton {
                    th: root.th
                    text: "Cancel"
                    onClicked: root.close()
                }
                AppButton {
                    th: root.th
                    text: "Save"
                    variant: "solid"
                    onClicked: root.save()
                }
            }
        }
    }
}
