import QtQuick

CardFrame {
    id: root

    readonly property var calendarData: {
        try { return JSON.parse(root.app.calendarJson); }
        catch (e) { return { calendars: [], dateLinks: [] }; }
    }
    readonly property var calendars: calendarData.calendars || []
    readonly property var links: calendarData.dateLinks || []
    readonly property string todayKey: dateKey(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())

    property int viewYear: (card.viewYear !== undefined) ? card.viewYear : new Date().getFullYear()
    property int viewMonth: (card.viewMonth !== undefined) ? card.viewMonth : new Date().getMonth()
    property var selectedIds: (card.calendarIds) ? card.calendarIds : []
    property string selectedDate: todayKey

    function dateKey(y, m, d) {
        var mm = m + 1;
        return y + "-" + (mm < 10 ? "0" : "") + mm + "-" + (d < 10 ? "0" : "") + d;
    }

    function prettyDate(key) {
        var p = key.split("-");
        if (p.length !== 3) return key;
        var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
        return d.toLocaleDateString(Qt.locale(), "ddd, MMM d");
    }

    function monthLabel() {
        var d = new Date(viewYear, viewMonth, 1);
        return d.toLocaleDateString(Qt.locale(), "MMMM yyyy");
    }

    function calendarColor(id) {
        for (var i = 0; i < calendars.length; i++)
            if (calendars[i].id === id) return calendars[i].color || root.th.accent;
        return root.th.accent;
    }

    function visibleLink(link) {
        if (selectedIds.length === 0) return true;
        for (var i = 0; i < link.calendarIds.length; i++)
            if (selectedIds.indexOf(link.calendarIds[i]) >= 0) return true;
        return false;
    }

    function linksFor(date) {
        return links.filter(function (link) {
            return link.date === date && visibleLink(link);
        });
    }

    function marksMap() {
        var map = {};
        for (var i = 0; i < links.length; i++) {
            var link = links[i];
            if (!visibleLink(link)) continue;
            if (!map[link.date]) map[link.date] = [];
            if (map[link.date].length < 3)
                map[link.date].push(calendarColor(link.calendarIds[0]));
        }
        return map;
    }

    function shiftMonth(delta) {
        var d = new Date(viewYear, viewMonth + delta, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
        selectedDate = dateKey(viewYear, viewMonth, 1);
        commitView();
    }

    function goToday() {
        var now = new Date();
        viewYear = now.getFullYear();
        viewMonth = now.getMonth();
        selectedDate = todayKey;
        commitView();
    }

    function commitView() {
        root.commit({
            viewYear: viewYear,
            viewMonth: viewMonth,
            calendarIds: selectedIds
        });
    }

    function toggleCalendar(id) {
        var next = selectedIds.slice();
        var at = next.indexOf(id);
        if (at >= 0) next.splice(at, 1);
        else next.push(id);
        selectedIds = next;
        root.commit({ calendarIds: next });
    }

    function showAll() {
        selectedIds = [];
        root.commit({ calendarIds: [] });
    }

    onCardChanged: {
        if (card.viewYear !== undefined && card.viewYear !== viewYear) viewYear = card.viewYear;
        if (card.viewMonth !== undefined && card.viewMonth !== viewMonth) viewMonth = card.viewMonth;
        if (card.calendarIds && JSON.stringify(card.calendarIds) !== JSON.stringify(selectedIds))
            selectedIds = card.calendarIds;
    }

    Component.onCompleted: {
        var now = new Date();
        if (viewYear === now.getFullYear() && viewMonth === now.getMonth())
            selectedDate = todayKey;
        else
            selectedDate = dateKey(viewYear, viewMonth, 1);
    }

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 30

        Row {
            anchors.fill: parent
            spacing: root.th.space1
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-left"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: root.shiftMonth(-1) }
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-right"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: root.shiftMonth(1) }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 116
                text: root.monthLabel()
                color: root.th.text
                elide: Text.ElideRight
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                font.weight: root.th.fontWeightMedium
            }

            AppButton {
                anchors.verticalCenter: parent.verticalCenter
                th: root.th
                text: "Today"
                onClicked: root.goToday()
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "settings"
                size: root.th.iconSmall
                color: root.th.text2
                TapHandler { onTapped: root.calendarManagerRequested() }
            }
        }
    }

    Flow {
        id: filters
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: childrenRect.height
        spacing: root.th.spaceTight
        Rectangle {
            height: 22
            width: allLabel.width + 16
            radius: root.th.radiusWide
            color: root.selectedIds.length === 0 ? root.th.hover : "transparent"
            border.width: root.th.borderWidth
            border.color: root.selectedIds.length === 0 ? root.th.accent : root.th.border

            Text {
                id: allLabel
                anchors.centerIn: parent
                text: "All"
                color: root.th.text2
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
                font.weight: root.th.fontWeightMedium
            }
            TapHandler { onTapped: root.showAll() }
        }

        Repeater {
            model: root.calendars

            delegate: Rectangle {
                required property var modelData
                height: 22
                width: chipLabel.width + 26
                radius: root.th.radiusWide
                color: root.selectedIds.indexOf(modelData.id) >= 0 ? root.th.hover : "transparent"
                border.width: root.th.borderWidth
                border.color: root.selectedIds.indexOf(modelData.id) >= 0 ? root.th.accent : root.th.border

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: modelData.color || root.th.accent
                }
                Text {
                    id: chipLabel
                    anchors.left: parent.left
                    anchors.leftMargin: 18
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

    CalendarGrid {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: filters.bottom
        anchors.topMargin: 6
        height: Math.min(width * 0.82, parent.height * 0.52)
        th: root.th
        year: root.viewYear
        month: root.viewMonth
        selectedDate: root.selectedDate
        todayDate: root.todayKey
        marks: root.marksMap()
        onDateSelected: function (date) { root.selectedDate = date; }
    }

    Rectangle {
        id: divider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: grid.bottom
        anchors.topMargin: 6
        height: 1
        color: root.th.border
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 6

        Row {
            id: agendaHeader
            width: parent.width
            height: 24
            spacing: root.th.spaceCompact
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - addButton.width - 6
                text: root.prettyDate(root.selectedDate)
                color: root.th.text2
                elide: Text.ElideRight
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeCaption
                font.weight: root.th.fontWeightMedium
            }
            AppButton {
                id: addButton
                anchors.verticalCenter: parent.verticalCenter
                th: root.th
                icon: "plus"
                text: "Reminder"
                onClicked: root.dateLinkRequested("", "", "", root.selectedDate)
            }
        }

        ListView {
            id: agenda
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: agendaHeader.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            clip: true
            spacing: root.th.spaceHalf
            model: root.linksFor(root.selectedDate)

            delegate: Item {
                required property var modelData
                width: agenda.width
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: rowHover.hovered ? root.th.hover : "transparent"
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.calendarColor(modelData.calendarIds[0])
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 26
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title || "(untitled)"
                    color: modelData.done ? root.th.muted : root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    font.strikeout: modelData.done
                    elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.sourceKind || "reminder"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeMicro
                }
                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    name: "square-pen"
                    size: root.th.iconSmall
                    color: root.th.muted
                    opacity: rowHover.hovered ? 1 : 0
                }
                HoverHandler { id: rowHover }
                TapHandler {
                    onTapped: root.dateLinkRequested("", "", modelData.id, modelData.date)
                }
            }
        }
    }
}
