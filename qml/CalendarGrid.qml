import QtQuick

Item {
    id: root

    property var th
    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()
    property string selectedDate: ""
    property string todayDate: ""
    property var marks: ({})

    signal dateSelected(string date)

    readonly property var weekDays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property int firstOffset: new Date(year, month, 1).getDay()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

    function dateKey(day) {
        var m = month + 1;
        return year + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day;
    }

    Column {
        anchors.fill: parent
        spacing: root.th.spaceHalf
        Row {
            width: parent.width
            height: 24

            Repeater {
                model: root.weekDays
                delegate: Text {
                    required property string modelData
                    width: parent.width / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    font.weight: root.th.fontWeightMedium
                }
            }
        }

        Grid {
            width: parent.width
            height: parent.height - 26
            columns: 7
            rows: 6

            Repeater {
                model: 42

                delegate: Item {
                    required property int index
                    property int day: index - root.firstOffset + 1
                    property bool valid: day >= 1 && day <= root.daysInMonth
                    property string key: valid ? root.dateKey(day) : ""
                    property bool selected: valid && key === root.selectedDate
                    property bool today: valid && key === root.todayDate
                    property var dots: valid ? (root.marks[key] || []) : []

                    width: parent.width / 7
                    height: parent.height / 6

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 4
                        height: width
                        radius: width / 2
                        color: root.today ? Qt.rgba(Qt.color(root.th.accent).r, Qt.color(root.th.accent).g, Qt.color(root.th.accent).b, 0.16) : "transparent"
                        border.width: selected ? 1.2 : 0
                        border.color: root.th.accent
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        visible: valid
                        text: day
                        color: selected || today ? root.th.text : root.th.text2
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeBody
                        font.weight: selected || today ? 600 : 400
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        spacing: root.th.spaceHalf
                        visible: dots.length > 0

                        Repeater {
                            model: Math.min(3, dots.length)
                            delegate: Rectangle {
                                required property int index
                                width: 4
                                height: 4
                                radius: 2
                                color: dots[index] || root.th.accent
                            }
                        }
                    }

                    TapHandler {
                        enabled: valid
                        onTapped: root.dateSelected(key)
                    }
                }
            }
        }
    }
}
