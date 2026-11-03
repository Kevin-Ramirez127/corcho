import QtQuick

CardFrame {
    id: root

    property string url: (card.url) || ""
    property string errorText: ""
    readonly property var gitInfo: {
        try { return card.gitData ? card.gitData : {}; } catch (e) { return {}; }
    }
    readonly property var lastCommit: gitInfo.lastCommit || ({})
    readonly property var ci: gitInfo.ci || ({})

    function refresh() {
        if (!root.app || !root.card) return;
        if (root.url.trim() !== "") root.app.gitCardRefresh(root.card.id);
    }

    function relative(value) {
        if (!value) return "";
        var then = new Date(value).getTime();
        if (isNaN(then)) return "";
        var seconds = Math.max(0, Math.floor((Date.now() - then) / 1000));
        if (seconds < 60) return "now";
        if (seconds < 3600) return Math.floor(seconds / 60) + "m ago";
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago";
        return Math.floor(seconds / 86400) + "d ago";
    }

    function ciColor(status) {
        if (status === "success") return root.th.success;
        if (status === "failure" || status === "failed" || status === "error") return root.th.danger;
        if (status === "pending" || status === "running" || status === "queued") return root.th.accent;
        return root.th.text2;
    }

    onUrlChanged: if (root.app && root.card) refresh()
    onAppChanged: refresh()
    Component.onCompleted: if (root.app && root.card) refresh()

    Timer {
        interval: 300000
        repeat: true
        running: root.visible && root.url !== ""
        onTriggered: root.refresh()
    }

    Column {
        anchors.fill: parent
        spacing: root.th.space2

        Row {
            width: parent.width
            spacing: root.th.space2
            AppTextField {
                width: parent.width - 96
                th: root.th
                text: root.url
                placeholder: "owner/repo or repository URL"
                onCommitted: function (value) {
                    root.url = value;
                    root.commit({ url: value });
                    root.refresh();
                }
            }
            AppButton {
                th: root.th
                icon: "refresh-cw"
                text: "Sync"
                onClicked: root.refresh()
            }
        }

        Text {
            width: parent.width
            visible: root.url === ""
            text: "Paste a GitHub, GitLab, Forgejo or Gitea repository URL."
            color: root.th.muted
            wrapMode: Text.WordWrap
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
        }

        Text {
            width: parent.width
            visible: root.gitInfo.error !== undefined
            text: root.gitInfo.error || ""
            color: root.th.danger
            wrapMode: Text.WordWrap
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
        }

        Row {
            visible: root.url !== "" && root.gitInfo.error === undefined
            spacing: root.th.space4

            Column {
                spacing: 1
                Text {
                    text: root.gitInfo.issues !== undefined ? root.gitInfo.issues : "—"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeLarge
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Issues"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeCaption
                }
            }
            Column {
                spacing: 1
                Text {
                    text: root.gitInfo.pullRequests !== undefined ? root.gitInfo.pullRequests : "—"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeLarge
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Pull requests"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeCaption
                }
            }
            Item { width: 1; height: 1 }
            Rectangle {
                visible: root.lastCommit.sha !== undefined
                height: 24
                width: ciLabel.width + 20
                radius: root.th.radiusWide
                color: "transparent"
                border.width: root.th.borderWidth
                border.color: root.ciColor(root.ci.status)
                Text {
                    id: ciLabel
                    anchors.centerIn: parent
                    text: "CI " + (root.ci.status || "unknown")
                    color: root.ciColor(root.ci.status)
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeCaption
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.th.border
        }

        Text {
            width: parent.width
            text: root.lastCommit.message || (root.url === "" ? "" : "No commits loaded")
            color: root.th.text
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeBody
        }

        Text {
            width: parent.width
            visible: root.lastCommit.sha !== undefined
            text: (root.lastCommit.sha || "") + (root.lastCommit.author ? " · " + root.lastCommit.author : "")
                  + (root.lastCommit.date ? " · " + root.relative(root.lastCommit.date) : "")
            color: root.th.muted
            elide: Text.ElideRight
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeCaption
        }
    }
}
