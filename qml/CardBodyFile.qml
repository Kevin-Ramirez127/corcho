import QtQuick
import QtWebEngine

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

    onPathChanged: load()
    onFileKindChanged: load()
    onAppChanged: load()
    Component.onCompleted: load()

    Column {
        anchors.fill: parent
        spacing: root.th.space2

        Row {
            width: parent.width
            height: 26
            spacing: root.th.space2
            Text {
                width: parent.width - 86
                text: root.path || root.fileName
                color: root.th.text2
                elide: Text.ElideMiddle
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
            AppButton {
                th: root.th
                icon: "external-link"
                text: "Open"
                onClicked: root.app.openPath(root.path)
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "refresh-cw"
                size: root.th.iconBody
                color: root.th.text2
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

        WebEngineView {
            visible: root.fileKind === "pdf" && root.errorText === ""
            width: parent.width
            height: parent.height - 34
            url: root.fileKind === "pdf" && root.path !== "" ? root.fileUrl() : "about:blank"
            zoomFactor: 1.0
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
                    name: modelData.isDir ? "folder-plus" : (modelData.kind === "image" ? "image" : "file-text")
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
                TapHandler { onTapped: root.app.openPath(modelData.path) }
            }
        }
    }
}
