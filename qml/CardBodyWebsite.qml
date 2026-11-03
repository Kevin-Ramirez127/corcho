import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

CardFrame {
    id: root

    property string url: (card.url) || ""
    property bool blocking: false
    property string debugOutput: ""
    property real webZoom: 1.0
    property bool asleep: false
    property bool noSleep: card ? !!card.noSleep : false
    property var webProfile: null

    readonly property bool sharedProfile: !root.settings || root.settings.web_shared_profile !== false
    readonly property var view: webLoader.item
    readonly property bool canGoBack: view ? view.canGoBack : false
    readonly property bool canGoForward: view ? view.canGoForward : false
    readonly property int sleepMinutes: {
        var value = root.settings ? Number(root.settings.web_sleep_minutes) : 10;
        return isNaN(value) ? 10 : Math.max(0, Math.round(value));
    }

    onUrlChanged: {
        if (root.url !== "") root.asleep = false;
        if (root.url !== "" && view && view.url.toString() !== root.url)
            view.url = root.url;
    }
    onCardChanged: root.noSleep = card ? !!card.noSleep : false

    Timer {
        id: sleepTimer
        interval: root.sleepMinutes * 60000
        repeat: false
        running: root.url !== "" && !root.noSleep && root.sleepMinutes > 0 && !root.asleep && !root.cardHovered
        onTriggered: root.asleep = true
    }

    function normalize(value) {
        if (value === "") return "";
        if (!/^[a-zA-Z]+:/.test(value)) return "https://" + value;
        return value;
    }

    function openUrl() {
        var target = normalize(urlField.text);
        if (target === "") return;
        if (root.app.adblockCheck(target)) {
            root.app.toast("Blocked by the ad blocker");
            return;
        }
        root.url = target;
        root.asleep = false;
        if (view) view.url = target;
        sleepTimer.restart();
    }

    function wake() {
        root.asleep = false;
        sleepTimer.restart();
    }

    function toggleSleep() {
        root.noSleep = !root.noSleep;
        root.commit({ noSleep: root.noSleep });
        sleepTimer.restart();
    }

    WebEngineProfilePrototype {
        id: isolatedPrototype
    }

    property var isolatedProfile: null

    Component.onCompleted: {
        if (!root.sharedProfile) {
            isolatedPrototype.storageName = "corcho-site-" + root.card.id;
            isolatedProfile = isolatedPrototype.instance();
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.th.spaceCompact
        RowLayout {
            width: parent.width
            height: 30
            spacing: root.th.space1
            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: "chevron-left"
                size: root.th.iconBody
                color: root.canGoBack ? root.th.text2 : root.th.muted
                TapHandler { onTapped: if (root.canGoBack) root.view.goBack() }
            }
            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: "chevron-right"
                size: root.th.iconBody
                color: root.canGoForward ? root.th.text2 : root.th.muted
                TapHandler { onTapped: if (root.canGoForward) root.view.goForward() }
            }
            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: "refresh-cw"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: if (root.view) root.view.reload() }
            }

            AppTextField {
                id: urlField
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                height: 30
                inputHeight: 30
                th: root.th
                text: root.url
                placeholder: "https://"
                onAccepted: root.openUrl()
            }

            Icon {
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 500
                name: "zoom-out"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: root.webZoom = Math.max(0.4, root.webZoom - 0.1) }
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 500
                text: Math.round(root.webZoom * 100) + "%"
                color: root.th.muted
                font.family: root.th.fontMono
                font.pixelSize: root.th.fontSizeSmall
            }
            Icon {
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 500
                name: "zoom-in"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: root.webZoom = Math.min(2.5, root.webZoom + 0.1) }
            }
            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: "external-link"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: root.app.openExternal(root.url) }
            }
            Icon {
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 400
                name: "coffee"
                size: root.th.iconBody
                color: root.noSleep ? root.th.accent : root.th.muted
                TapHandler { onTapped: root.toggleSleep() }
            }
            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: "shield"
                size: root.th.iconBody
                color: root.app.adblockCheck(root.url) ? root.th.accent : root.th.muted
                TapHandler { onTapped: debugPopup.open() }
            }
        }

        Item {
            width: parent.width
            height: parent.height - 36

            Text {
                anchors.centerIn: parent
                visible: root.url === ""
                width: parent.width - 48
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Enter a URL to load a website"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }

            Column {
                anchors.centerIn: parent
                spacing: root.th.space2
                visible: root.url !== "" && root.asleep
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Sleeping to save memory"
                    color: root.th.muted
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeSmall
                }
                AppButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    th: root.th
                    icon: "play"
                    text: "Wake"
                    onClicked: root.wake()
                }
            }

            Loader {
                id: webLoader
                anchors.fill: parent
                active: root.url !== "" && !root.asleep && (!root.sharedProfile || root.webProfile !== null)
                sourceComponent: webComponent
            }

            Component {
                id: webComponent

                WebEngineView {
                    anchors.fill: parent
                    profile: root.sharedProfile && root.webProfile ? root.webProfile : root.isolatedProfile
                    zoomFactor: root.webZoom

                    Component.onCompleted: if (root.url !== "") url = root.url

                    onUrlChanged: {
                        if (!root.app || root.blocking) return;
                        if (root.app.adblockCheck(url)) {
                            root.blocking = true;
                            root.app.toast("Blocked " + url);
                            url = "about:blank";
                            root.blocking = false;
                            return;
                        }
                        urlField.text = url;
                    }

                    onLoadingChanged: function (loadRequest) {
                        if (!root.app) return;
                        if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                            var hosts = root.app.adblockHosts();
                            runJavaScript(
                                "(function(){var blocked=" + hosts + ";" +
                                "function hit(u){try{var h=new URL(u,location.href).hostname;return blocked.some(function(b){return h===b||h.endsWith('.'+b);});}catch(e){return false;}}" +
                                "var f=window.fetch;window.fetch=function(u,o){var url=(typeof u==='string')?u:(u&&u.url)||'';if(hit(url))return Promise.reject(new Error('blocked by Corcho'));return f.apply(this,arguments);};" +
                                "var xo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){this.__blocked=hit(u);return xo.apply(this,arguments);};" +
                                "var xs=XMLHttpRequest.prototype.send;XMLHttpRequest.prototype.send=function(){if(this.__blocked){this.abort();return;}return xs.apply(this,arguments);};" +
                                "var sels=['[id^=google_ads]','[id^=div-gpt-ad]','[class*=sponsored]','iframe[src*=doubleclick]','iframe[src*=googlesyndication]'];" +
                                "sels.forEach(function(s){document.querySelectorAll(s).forEach(function(n){n.remove();});});})()"
                            );
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: debugPopup
        width: Math.min(640, root.width - 40)
        height: Math.min(520, root.height - 40)
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 14

        background: Rectangle {
            radius: root.th.radiusCard
            color: root.th.menu
            border.width: root.th.borderWidth
            border.color: root.th.border
        }

        contentItem: Column {
            spacing: root.th.spaceSnug
            Row {
                spacing: root.th.space2
                Text {
                    text: "Website session"
                    color: root.th.text
                    font.family: root.th.fontFamily
                    font.pixelSize: root.th.fontSizeBody
                    font.weight: root.th.fontWeightMedium
                }
                Item { width: 1; height: 1 }
            }

            Row {
                spacing: root.th.space2
                AppButton {
                    th: root.th
                    icon: "cookie"
                    text: "Read cookies"
                    onClicked: if (root.view) root.view.runJavaScript("document.cookie", function (value) {
                        root.debugOutput = "document.cookie:\n" + value;
                    })
                }
                AppButton {
                    th: root.th
                    icon: "shield"
                    text: "Run session probe"
                    onClicked: root.runProbe()
                }
            }

            TextEdit {
                width: parent.width
                height: parent.height - 84
                text: root.debugOutput
                readOnly: true
                selectByMouse: true
                color: root.th.text2
                font.family: root.th.fontMono
                font.pixelSize: root.th.fontSizeSmall
                wrapMode: TextEdit.WrapAnywhere
                clip: true
            }
        }
    }

    function runProbe() {
        var script = `
        (function () {
            var out = [];
            out.push("=== Cross-Origin Session Probe ===");
            out.push("document.cookie: " + (document.cookie || "(empty)"));
            var targets = [
                ["Google", "https://www.google.com/"],
                ["Wikipedia", "https://en.wikipedia.org/w/api.php?action=query&meta=siteinfo&format=json"],
                ["Hacker News", "https://hacker-news.firebaseio.com/v0/topstories.json"],
                ["Open-Meteo", "https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.41&current=temperature_2m"]
            ];
            var pending = targets.length;
            targets.forEach(function (t) {
                fetch(t[1], { credentials: "include", mode: "cors" })
                    .then(function (r) { return r.text().then(function (b) {
                        out.push((r.status < 400 && b.length > 0 ? "[LEAK] " : "[BLOCKED] ") + t[0] + ": " + r.status + " (" + b.length + "b)");
                    }); })
                    .catch(function (e) { out.push("[BLOCKED] " + t[0] + ": " + e.message); })
                    .finally(function () {
                        pending -= 1;
                        if (pending === 0) {
                            out.push("Verdict: cross-origin reads finished.");
                            window.__corchoProbe = out.join("\\n");
                        }
                    });
            });
            out.push("Running probes...");
            return out.join("\\n");
        })()`;
        if (!root.view) return;
        root.view.runJavaScript(script, function (value) {
            root.debugOutput = String(value || "");
            setTimeout(function () {
                if (root.view) root.view.runJavaScript("window.__corchoProbe || ''", function (final) {
                    if (final) root.debugOutput = String(final);
                });
            }, 2500);
        });
    }
}
