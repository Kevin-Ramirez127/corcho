import QtQuick

CardFrame {
    id: root

    property string apiUrl: (card.apiUrl) || ""
    property string method: (card.method) || "GET"
    property string lastBody: (card.lastBody) || ""
    property string status: ""
    property bool busy: false

    function fetch() {
        if (apiUrl === "") return;
        busy = true;
        status = "Fetching";
        var xhr = new XMLHttpRequest();
        xhr.open(method, apiUrl);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            busy = false;
            status = "HTTP " + xhr.status;
            lastBody = xhr.responseText || "";
            root.commit({ apiUrl: root.apiUrl, method: root.method, lastBody: root.lastBody, status: xhr.status });
        };
        xhr.send();
    }

    Column {
        anchors.fill: parent
        spacing: root.th.space2
        Row {
            width: parent.width
            spacing: root.th.spaceCompact
            SelectField {
                id: methodField
                th: root.th
                width: 96
                value: root.method
                options: [
                    { value: "GET", label: "GET" },
                    { value: "POST", label: "POST" },
                    { value: "PUT", label: "PUT" },
                    { value: "DELETE", label: "DELETE" }
                ]
                onSelected: function (value) { root.method = value; }
            }

            AppTextField {
                width: parent.width - 96 - 78
                th: root.th
                text: root.apiUrl
                placeholder: "https://api.example.com/data"
                inputHeight: 34
                onEdited: function (value) { root.apiUrl = value; }
                onAccepted: root.fetch()
            }

            AppButton {
                th: root.th
                width: 72
                icon: root.busy ? "refresh-cw" : "download-cloud"
                text: "Fetch"
                onClicked: root.fetch()
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.th.border
        }

        Row {
            spacing: root.th.space2
            Text {
                text: root.status
                color: root.th.muted
                font.family: root.th.fontMono
                font.pixelSize: root.th.fontSizeSmall
            }
            Text {
                text: "JSON response"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }

        TextEdit {
            width: parent.width
            height: parent.height - 84
            text: root.lastBody
            readOnly: true
            selectByMouse: true
            color: root.th.text2
            font.family: root.th.fontMono
            font.pixelSize: root.th.fontSizeSmall
            wrapMode: TextEdit.WrapAnywhere
            clip: true

            Text {
                anchors.fill: parent
                visible: parent.text.length === 0
                text: "Run a request to see the response"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }
    }
}
