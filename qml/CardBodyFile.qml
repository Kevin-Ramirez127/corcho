import QtQuick

CardFrame {
    id: root

    property string path: (card.path) || ""
    property string fileKind: (card.fileKind) || ""
    property string fileName: (card.name) || ""
    property string markdown: ""
    property var folderEntries: []
    property string errorText: ""

    function fileUrl() {
        return "file://" + encodeURI(root.path);
    }

    function load() {
        if (!root.app) return;
        errorText = "";
        markdown = "";
        folderEntries = [];
        if (root.path === "") {
            errorText = "No file selected.";
            return;
        }
        if (root.fileKind === "markdown") {
            var text = String(root.app.readPinnedFile(root.path));
            if (text.indexOf("error:") === 0) errorText = text.slice(6);
            else markdown = text;
        } else if (root.fileKind === "folder") {
            var raw = String(root.app.listPinnedFolder(root.path));
            if (raw.indexOf("error:") === 0) {
                errorText = raw.slice(6);
                return;
            }
            try {
                var data = JSON.parse(raw);
                folderEntries = data.entries || [];
            } catch (e) {
                errorText = String(e);
            }
        }
    }

    function nextPosition() {
        var z = Math.max(0.2, root.app.zoom || 1);
        var vw = root.app.viewportWidth || 1000;
        var left = -root.app.panX / z;
        var right = left + vw / z;
        var px = root.card ? root.card.x : 64;
        var py = root.card ? root.card.y : 64;
        var pw = root.card ? root.card.width : 480;
        var ph = root.card ? root.card.height : 360;
        if (px + pw + 32 + 480 <= right) return { x: px + pw + 32, y: py };
        var y = py + ph + 32;
        var cards = [];
        try { cards = JSON.parse(root.app.cardsJson); } catch (e) {}
        for (var i = 0; i < cards.length; i++) {
            var c = cards[i];
            if (Math.abs(c.x - px) < 64) y = Math.max(y, c.y + c.height + 32);
        }
        return { x: px, y: y };
    }

    function entryIcon(entry) {
        if (entry.isDir) return "folder-plus";
        if (entry.kind === "image") return "image";
        if (entry.kind === "pdf" || entry.kind === "markdown") return "file-text";
        return "file";
    }

    function openEntry(entry) {
        if (!root.app) return;
        var supported = entry.isDir || entry.kind === "image" || entry.kind === "markdown";
        if (supported) {
            var pos = root.nextPosition();
            var raw = String(root.app.pinPath(String(entry.path), pos.x, pos.y, root.gridId));
            if (raw.indexOf("error:") === 0) root.errorText = raw.slice(6);
        } else {
            root.app.openPath(String(entry.path));
        }
    }

    onPathChanged: load()
    onFileKindChanged: load()
    onAppChanged: load()
    Component.onCompleted: load()

    Column {
        anchors.fill: parent
        spacing: root.th.space2

        Row {
            width: parent.width
            height: 24
            spacing: root.th.space2

            Text {
                width: parent.width - 56
                anchors.verticalCenter: parent.verticalCenter
                text: root.path || root.fileName
                color: root.th.text2
                elide: Text.ElideMiddle
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }

            Item {
                id: openExternally
                width: 26
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                Accessible.role: Accessible.Button
                Accessible.name: "Open in default application"

                Rectangle {
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: openHover.hovered ? root.th.hover : "transparent"
                    border.width: 1
                    border.color: openHover.hovered ? root.th.borderStrong : root.th.border
                }
                Icon {
                    anchors.centerIn: parent
                    name: "external-link"
                    size: 13
                    color: root.th.text2
                }
                HoverHandler { id: openHover }
                TapHandler { onTapped: root.app.openPath(root.path) }
            }

            Item {
                width: 18
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                Icon {
                    anchors.centerIn: parent
                    name: "refresh-cw"
                    size: 13
                    color: root.th.text2
                }
                TapHandler { onTapped: root.load() }
            }
        }

        Text {
            width: parent.width
            visible: root.errorText !== ""
            text: root.errorText
            color: root.th.danger
            wrapMode: Text.WordWrap
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
        }

        Image {
            visible: root.fileKind === "image" && root.errorText === ""
            width: parent.width
            height: parent.height - 34
            source: root.fileKind === "image" && root.path !== "" ? root.fileUrl() : ""
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            onStatusChanged: if (root.fileKind === "image" && status === Image.Error) root.errorText = "Could not load this image."
        }

        Column {
            visible: root.fileKind === "pdf" && root.errorText === ""
            width: parent.width
            spacing: root.th.space2
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "PDFs open in your default viewer to keep Corcho light."
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
            AppButton {
                anchors.horizontalCenter: parent.horizontalCenter
                th: root.th
                icon: "external-link"
                text: "Open PDF"
                onClicked: root.app.openPath(root.path)
            }
        }

        Flickable {
            visible: root.fileKind === "markdown" && root.errorText === ""
            width: parent.width
            height: parent.height - 34
            contentWidth: width
            contentHeight: markdownView.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
                id: markdownView
                width: parent.width
                text: root.markdown
                textFormat: Text.MarkdownText
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                wrapMode: Text.Wrap
                lineHeight: root.th.lineHeightNormal
            }
        }

        ListView {
            visible: root.fileKind === "folder" && root.errorText === ""
            width: parent.width
            height: parent.height - 34
            clip: true
            spacing: root.th.space1
            model: root.folderEntries

            delegate: Item {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: root.th.radiusKeycap
                    color: rowHover.hovered ? root.th.hover : "transparent"
                }
                Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.entryIcon(modelData)
                    size: root.th.iconBody
                    color: root.th.text2
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.th.text
                    elide: Text.ElideRight
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                HoverHandler { id: rowHover }
                TapHandler {
                    onTapped: root.openEntry({
                        path: String(modelData.path),
                        kind: String(modelData.kind),
                        isDir: !!modelData.isDir
                    })
                }
            }
        }
    }
}
