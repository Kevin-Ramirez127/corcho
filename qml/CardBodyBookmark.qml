import QtQuick

CardFrame {
    id: root

    property string url: (card.url) || ""
    property string domain: {
        var m = url.match(/^https?:\/\/([^\/]+)/i);
        return m ? m[1].replace(/^www\./, "") : url;
    }

    function open() {
        if (root.url !== "") root.app.openExternal(root.url);
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: 40
                height: 40
                radius: 10
                color: root.th.surfaceStrong

                Text {
                    anchors.centerIn: parent
                    text: root.domain.length > 0 ? root.domain.charAt(0).toUpperCase() : "?"
                    color: root.th.accent
                    font.family: root.th.fontFamily
                    font.pixelSize: 18
                    font.weight: 500
                }
            }

            Column {
                width: parent.width - 50
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.domain || "Add a URL"
                    color: root.th.text
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: 13
                    font.weight: 500
                }
                Text {
                    width: parent.width
                    text: root.url
                    color: root.th.muted
                    elide: Text.ElideMiddle
                    font.family: root.th.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        AppTextField {
            width: parent.width
            th: root.th
            text: root.url
            placeholder: "https://"
            inputHeight: 32
            onEdited: function (value) { root.url = value; }
            onAccepted: root.commit({ url: root.url })
        }

        AppButton {
            th: root.th
            icon: "external-link"
            text: "Open"
            onClicked: root.open()
        }
    }

}
