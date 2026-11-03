import QtQuick

Item {
    id: root

    property var app
    property var th
    property bool opened: false
    property int step: 0
    property string remote: ""
    property string branch: "main"
    property bool autoPull: true
    property bool autoPush: true
    property bool attachments: false
    property string auth: "system"
    property string errorText: ""

    signal closed()

    anchors.fill: parent
    visible: opened
    z: 640

    function open() {
        var s = {};
        try { s = JSON.parse(root.app.settingsJson || "{}"); } catch (e) { s = {}; }
        remote = s.git_remote || "";
        branch = s.git_branch || "main";
        autoPull = s.git_auto_pull !== false;
        autoPush = s.git_auto_push !== false;
        attachments = s.git_include_attachments === true;
        auth = s.git_auth || "system";
        step = 0;
        errorText = "";
        opened = true;
        remoteField.input.forceActiveFocus();
    }

    function close() {
        opened = false;
        root.closed();
    }

    function set(key, value) {
        root.app.setSetting(key, JSON.stringify(value));
    }

    function remoteLooksValid() {
        var value = remote.trim();
        return value.indexOf("://") > 0 || value.indexOf("@") === 0 || value.indexOf(":") > 0;
    }

    function next() {
        errorText = "";
        if (step === 0) {
            if (!remoteLooksValid()) {
                errorText = "Enter a Git remote such as git@github.com:you/corcho-data.git or https://…";
                return;
            }
            if (branch.trim() === "") {
                errorText = "Enter a branch name.";
                return;
            }
        }
        step = Math.min(2, step + 1);
    }

    function finish() {
        set("git_remote", remote.trim());
        set("git_branch", branch.trim() || "main");
        set("git_auto_pull", autoPull);
        set("git_auto_push", autoPush);
        set("git_include_attachments", attachments);
        set("git_auth", auth);
        set("git_sync_enabled", true);
        close();
        root.app.gitSyncNow();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea {
            anchors.fill: parent
            onClicked: function (mouse) {
                var p = panel.mapFromItem(root, mouse.x, mouse.y);
                if (p.x < 0 || p.y < 0 || p.x > panel.width || p.y > panel.height)
                    root.close();
            }
        }
    }

    Rectangle {
        id: panel
        width: Math.min(560, root.width - 32)
        height: Math.min(500, root.height - 32)
        anchors.centerIn: parent
        radius: root.th.radiusPanel
        color: root.th.menu
        border.width: root.th.borderWidth
        border.color: root.th.border

        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: root.th.space5
            spacing: root.th.space4

            Row {
                width: parent.width
                height: 26
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28
                    text: "Set up Git sync"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizePage
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

            Row {
                width: parent.width
                spacing: root.th.space2
                Repeater {
                    model: ["Remote", "Options", "Review"]
                    delegate: Text {
                        required property string modelData
                        required property int index
                        text: (index + 1) + ". " + modelData
                        color: index === root.step ? root.th.accent : root.th.muted
                        font.family: root.th.fontFamily
                        font.pixelSize: root.th.fontSizeSmall
                        font.weight: index === root.step ? root.th.fontWeightMedium : root.th.fontWeightRegular
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: root.th.borderWidth
                color: root.th.border
            }

            Column {
                width: parent.width
                spacing: root.th.space3
                visible: root.step === 0

                Text {
                    width: parent.width
                    text: "Corcho commits workspace.json to a Git repository you control. Use an SSH or HTTPS URL."
                    color: root.th.text2
                    wrapMode: Text.WordWrap
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    lineHeight: root.th.lineHeightNormal
                }
                Text {
                    text: "Remote URL"
                    color: root.th.text2
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                AppTextField {
                    id: remoteField
                    width: parent.width
                    th: root.th
                    text: root.remote
                    placeholder: "git@github.com:you/corcho-data.git"
                    onEdited: function (value) { root.remote = value; }
                }
                Text {
                    text: "Branch"
                    color: root.th.text2
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                AppTextField {
                    width: parent.width
                    th: root.th
                    text: root.branch
                    placeholder: "main"
                    onEdited: function (value) { root.branch = value; }
                }
            }

            Column {
                width: parent.width
                spacing: root.th.space3
                visible: root.step === 1

                SettingRow {
                    th: root.th
                    title: "Pull at start"
                    description: "Fast-forward or union-merge the remote before loading."
                    ToggleSwitch {
                        th: root.th
                        checked: root.autoPull
                        onToggled: function (value) { root.autoPull = value; }
                    }
                }
                SettingRow {
                    th: root.th
                    title: "Push changes"
                    description: "Commit and push a couple of seconds after the last edit."
                    ToggleSwitch {
                        th: root.th
                        checked: root.autoPush
                        onToggled: function (value) { root.autoPush = value; }
                    }
                }
                SettingRow {
                    th: root.th
                    title: "Include attachments"
                    description: "Commit files from the attachments directory too."
                    ToggleSwitch {
                        th: root.th
                        checked: root.attachments
                        onToggled: function (value) { root.attachments = value; }
                    }
                }
                SettingRow {
                    th: root.th
                    title: "Authentication"
                    description: "gh CLI uses the local gh login instead of stored tokens."
                    SelectField {
                        width: 170
                        th: root.th
                        value: root.auth
                        options: [
                            { value: "system", label: "Git credentials" },
                            { value: "gh", label: "gh CLI" }
                        ]
                        onSelected: function (value) { root.auth = value; }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: root.th.space2
                visible: root.step === 2

                Text {
                    width: parent.width
                    text: "Ready to sync"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeTitle
                    font.weight: root.th.fontWeightMedium
                }
                Text {
                    width: parent.width
                    text: "Remote: " + root.remote + "\nBranch: " + root.branch +
                          "\nPull at start: " + (root.autoPull ? "on" : "off") +
                          "\nPush changes: " + (root.autoPush ? "on" : "off") +
                          "\nAttachments: " + (root.attachments ? "on" : "off") +
                          "\nAuthentication: " + (root.auth === "gh" ? "gh CLI" : "Git credentials")
                    color: root.th.text2
                    wrapMode: Text.WordWrap
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                    lineHeight: root.th.lineHeightNormal
                }
                Text {
                    width: parent.width
                    text: "The first sync commits the workspace and pushes it. Existing remotes are merged with union semantics."
                    color: root.th.muted
                    wrapMode: Text.WordWrap
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeCaption
                }
            }

            Text {
                width: parent.width
                text: root.errorText
                visible: root.errorText !== ""
                color: root.th.danger
                wrapMode: Text.WordWrap
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }

            Item { width: 1; height: 1 }

            Row {
                anchors.right: parent.right
                spacing: root.th.space2

                AppButton {
                    th: root.th
                    text: "Cancel"
                    onClicked: root.close()
                }
                AppButton {
                    th: root.th
                    text: "Back"
                    visible: root.step > 0
                    onClicked: root.step -= 1
                }
                AppButton {
                    th: root.th
                    text: root.step === 2 ? "Finish & sync" : "Next"
                    variant: "solid"
                    onClicked: root.step === 2 ? root.finish() : root.next()
                }
            }
        }
    }
}
