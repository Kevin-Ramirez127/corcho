import QtQuick
import QtQuick.Controls
import QtWebEngine

CardFrame {
    id: root

    property string url: (card.url) || ""
    property bool blocking: false
    property string debugOutput: ""

    onUrlChanged: {
        if (root.url !== "" && webView && webView.url.toString() !== root.url)
            webView.url = root.url;
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
        webView.url = target;
    }

    WebEngineProfile {
        id: profile
        storageName: "corcho-site-" + root.card.id
        offTheRecord: false
    }

    Column {
        anchors.fill: parent
        spacing: root.th.spaceCompact
        Row {
            width: parent.width
            height: 30
            spacing: root.th.space1
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-left"
                size: root.th.iconBody
                color: webView.canGoBack ? root.th.text2 : root.th.muted
                TapHandler { onTapped: if (webView.canGoBack) webView.goBack() }
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-right"
                size: root.th.iconBody
                color: webView.canGoForward ? root.th.text2 : root.th.muted
                TapHandler { onTapped: if (webView.canGoForward) webView.goForward() }
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "refresh-cw"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: webView.reload() }
            }

            AppTextField {
                id: urlField
                width: parent.width - 260
                height: 30
                inputHeight: 30
                th: root.th
                text: root.url
                placeholder: "https://"
                onAccepted: root.openUrl()
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "zoom-out"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: webView.zoomFactor = Math.max(0.4, webView.zoomFactor - 0.1) }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(webView.zoomFactor * 100) + "%"
                color: root.th.muted
                font.family: root.th.fontMono
                font.pixelSize: root.th.fontSizeSmall
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "zoom-in"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: webView.zoomFactor = Math.min(2.5, webView.zoomFactor + 0.1) }
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "external-link"
                size: root.th.iconBody
                color: root.th.text2
                TapHandler { onTapped: root.app.openExternal(webView.url) }
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "shield"
                size: root.th.iconBody
                color: root.app.adblockCheck(webView.url) ? root.th.accent : root.th.muted
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
                text: "Enter a URL to load a website in its own session"
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: root.th.fontSizeSmall
            }

        WebEngineView {
            id: webView
            anchors.fill: parent
            visible: root.url !== ""
            profile: profile
            zoomFactor: 1.0

            Component.onCompleted: if (root.url !== "") url = root.url

            onUrlChanged: {
                if (root.blocking) return;
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
                    onClicked: webView.runJavaScript("document.cookie", function (value) {
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
        webView.runJavaScript(script, function (value) {
            root.debugOutput = String(value || "");
            setTimeout(function () {
                webView.runJavaScript("window.__corchoProbe || ''", function (final) {
                    if (final) root.debugOutput = String(final);
                });
            }, 2500);
        });
    }
}
