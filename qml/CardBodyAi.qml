import QtQuick
import QtQuick.Controls

CardFrame {
    id: root

    property string prompt: (card.prompt) || ""
    property string context: (card.context) || ""
    property string output: (card.lastResult) || ""
    property string streamId: ""
    property bool busy: false
    property string errorText: ""
    property string presetId: (card.presetId) || ""
    readonly property var linkedIds: card && card.linkedIds ? card.linkedIds : []
    signal activated()

    function settings() {
        try { return JSON.parse(root.app.settingsJson); } catch (e) { return ({}); }
    }

    function cardTitle(id) {
        var list = [];
        try { list = JSON.parse(root.app.cardsJson); } catch (e) { list = []; }
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return list[i].title || list[i].type;
        }
        return id;
    }

    function otherCards() {
        var list = [];
        try { list = JSON.parse(root.app.cardsJson); } catch (e) { list = []; }
        var out = [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === root.card.id || list[i].type === "ai") continue;
            out.push(list[i]);
        }
        return out;
    }

    function presets() {
        var s = settings();
        var list = s.aiPresets || [];
        return Array.isArray(list) ? list : [];
    }

    function presetOptions() {
        var out = [{ value: "", label: "Settings default" }];
        var list = presets();
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            out.push({ value: p.id, label: p.name + " · " + p.provider + "/" + p.model });
        }
        return out;
    }

    function activePreset() {
        var list = presets();
        for (var i = 0; i < list.length; i++) if (list[i].id === root.presetId) return list[i];
        return null;
    }

    function run() {
        var s = settings();
        var preset = root.activePreset();
        var provider = preset ? preset.provider : (s.aiProvider || "claude");
        var model = preset ? preset.model : ((s.aiModel && s.aiModel[provider]) || "");
        var linked = root.app.aiContext(JSON.stringify(root.linkedIds));
        var manual = root.context.trim();
        var full = linked + (manual !== "" ? "\n\nUser context:\n" + manual : "");
        root.busy = true;
        root.errorText = "";
        root.output = "";
        root.commit({ prompt: root.prompt, context: root.context, presetId: root.presetId });
        root.activated();
        root.streamId = root.app.aiSend(provider, model, root.prompt, full);
    }

    Connections {
        target: root.app
        ignoreUnknownSignals: true
        function onAiChunk(id, chunk) {
            if (id === root.streamId) root.output += chunk;
        }
        function onAiDone(id, full) {
            if (id !== root.streamId) return;
            root.busy = false;
            root.output = full;
            root.commit({ prompt: root.prompt, context: root.context, lastResult: root.output });
        }
        function onAiError(id, message) {
            if (id !== root.streamId) return;
            root.busy = false;
            root.errorText = message;
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.th.space2
        SelectField {
            objectName: "aiPresetSelect"
            width: parent.width
            th: root.th
            value: root.presetId
            placeholder: "Settings default"
            options: root.presetOptions()
            onSelected: function (value) {
                root.presetId = value;
                root.commit({ presetId: value });
            }
        }
        TextEdit {
            id: promptEdit
            width: parent.width
            height: 64
            text: root.prompt
            color: root.th.text
            selectionColor: root.th.accent
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            clip: true
            onActiveFocusChanged: if (!activeFocus) root.commit({ prompt: text, context: root.context })

            CardTapHandler {
                acceptedButtons: Qt.LeftButton
                onAction: root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y)
            }

            Text {
                anchors.fill: parent
                visible: promptEdit.text.length === 0
                text: "Prompt"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }

        Row {
            width: parent.width
            spacing: root.th.space2
            AppButton {
                th: root.th
                icon: root.busy ? "refresh-cw" : "play"
                text: root.busy ? "Thinking" : "Run"
                variant: "solid"
                enabledButton: !root.busy && root.prompt.trim() !== ""
                onClicked: root.run()
            }
            AppButton {
                th: root.th
                icon: "link"
                text: root.linkedIds.length + " linked"
                onClicked: linkPopup.open()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var s = root.settings();
                    var p = s.aiProvider || "claude";
                    return (s.aiModel && s.aiModel[p]) ? s.aiModel[p] : p;
                }
                color: root.th.muted
                font.family: root.th.fontMono
                font.pixelSize: root.th.fontSizeSmall
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.th.border
        }

        TextEdit {
            width: parent.width
            height: parent.height - 156
            text: root.busy ? root.output + " ..." : (root.errorText !== "" ? root.errorText : root.output)
            readOnly: true
            selectByMouse: true
            color: root.errorText !== "" ? root.th.danger : root.th.text2
            font.family: root.th.fontFamily
            font.pixelSize: root.th.fontSizeSmall
            wrapMode: TextEdit.Wrap
            clip: true

            CardTapHandler {
                acceptedButtons: Qt.LeftButton
                onAction: root.requestBodySelect(point.modifiers, point.scenePosition.x, point.scenePosition.y)
            }

            Text {
                anchors.fill: parent
                visible: parent.text.length === 0
                text: "Output appears here"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }
        }
    }

    Popup {
        id: linkPopup
        objectName: "aiLinkPopup"
        anchors.centerIn: parent
        width: Math.min(360, root.width - 32)
        height: Math.min(320, root.height - 32)
        padding: 12
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: root.th.radiusCard
            color: root.th.menu
            border.width: root.th.borderWidth
            border.color: root.th.border
        }
        contentItem: Column {
            spacing: root.th.space1
            Text {
                width: parent.width
                text: "Send context from"
                color: root.th.text
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeBody
                font.weight: root.th.fontWeightMedium
            }
            ListView {
                width: parent.width
                height: parent.height - 28
                clip: true
                model: linkPopup.opened ? root.otherCards() : []
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: 36
                    Rectangle {
                        anchors.fill: parent
                        radius: root.th.radiusKeycap
                        color: rowHover.hovered ? root.th.hover : "transparent"
                    }
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: root.th.space2
                        spacing: root.th.space2
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.icon || "square"
                            size: root.th.iconBody
                            color: root.th.text2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 60
                            text: modelData.title || modelData.type
                            color: root.th.text
                            font.family: root.th.fontFamily
                            font.pixelSize: root.th.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.linkedIds.indexOf(modelData.id) >= 0
                            name: "check"
                            size: root.th.iconBody
                            color: root.th.accent
                        }
                    }
                    HoverHandler { id: rowHover }
                    CardTapHandler {
                        onAction: root.app.toggleAiLink(root.card.id, modelData.id)
                    }
                }
            }
        }
    }
}
