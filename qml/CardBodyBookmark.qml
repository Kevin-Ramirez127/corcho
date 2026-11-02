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
        spacing: root.th.space2
        Row {
            width: parent.width
            spacing: root.th.spaceSnug
            Rectangle {
                width: 40
                height: 40
                radius: root.th.radiusMenu
                color: root.th.surfaceStrong
                TapHandler { onTapped: root.open() }

                Text {
                    anchors.centerIn: parent
                    text: root.domain.length > 0 ? root.domain.charAt(0).toUpperCase() : "?"
                    color: root.th.accent
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizePage
                    font.weight: root.th.fontWeightMedium
                }
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "external-link"
                size: root.th.iconBody
                color: root.th.muted
                TapHandler { onTapped: root.open() }
            }

            Column {
                width: parent.width - 50
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.th.spaceHalf
                Text {
                    width: parent.width
                    text: root.domain || "Add a URL"
                    color: root.th.text
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    font.weight: root.th.fontWeightMedium
                }
                Text {
                    width: parent.width
                    text: root.url
                    color: root.th.muted
                    elide: Text.ElideMiddle
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
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
            onCommitted: function (value) {
                root.url = value;
                root.commit({ url: value });
            }
        }

    }

}
