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
    // The live page. Website cards hand this view to the picture-in-picture
    // copy of the card and take it back again instead of recreating it, so
    // the site is never reloaded just because the card moved.
    property WebEngineView hostedView: null
    // Set once the page lives somewhere else: this body must never spawn a
    // second copy of the site of its own.
    property bool viewReleased: false
    readonly property WebEngineView view: hostedView
    readonly property bool tooltipsEnabled:
        !root.settings || root.settings.show_card_tooltips !== false
    readonly property bool canGoBack: view ? view.canGoBack : false
    readonly property bool canGoForward: view ? view.canGoForward : false
    readonly property int sleepMinutes: {
        var value = root.settings ? Number(root.settings.web_sleep_minutes) : 10;
        return isNaN(value) ? 10 : Math.max(0, Math.round(value));
    }

    // QUrl rewrites a URL when it round-trips through the engine: a data:
    // URL gets its "<" and ">" percent-encoded, for example. Two strings that
    // denote the same page must never be pushed into the view again, because
    // assigning them reloads the site and throws away its state.
    function sameUrl(a, b) {
        if (a === b) return true;
        if (!a || !b) return false;
        function decoded(value) {
            try { return decodeURIComponent(value); } catch (e) { return value; }
        }
        return decoded(a) === decoded(b);
    }

    onUrlChanged: {
        if (root.url === "") {
            root.destroyView();
            return;
        }
        root.asleep = false;
        if (root.view && !root.sameUrl(root.view.url.toString(), root.url))
            root.view.url = root.url;
        root.ensureView();
    }
    onCardChanged: {
        root.noSleep = card ? !!card.noSleep : false;
        var next = card && card.url !== undefined ? (card.url || "") : "";
        if (!root.sameUrl(next, root.url)) root.url = next;
        else root.ensureView();
    }
    onSharedProfileChanged: {
        root.syncViewProfile();
        root.ensureView();
    }
    onWebProfileChanged: {
        root.syncViewProfile();
        root.ensureView();
    }
    onAsleepChanged: {
        if (root.asleep) root.destroyView();
        else root.ensureView();
    }
    onWebZoomChanged: {
        if (root.view && root.view.zoomFactor !== root.webZoom)
            root.view.zoomFactor = root.webZoom;
    }

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

    // The card body is destroyed while it is off screen and recreated in a
    // picture-in-picture window. Persist the current URL so those copies load
    // the same site instead of falling back to the empty start state.
    function persistUrl(value) {
        if (!root.card || value === "" || value === "about:blank") return;
        if ((root.card.url || "") === value) return;
        root.commit({ url: value });
    }

    // --- live page handoff ---------------------------------------------
    // Loading a site is expensive and loses all of its state, so the view is
    // created once and then moved between the canvas copy of the card and its
    // picture-in-picture copy.

    function ensureView() {
        if (root.hostedView || root.viewReleased || root.asleep || root.url === "")
            return null;
        // In shared mode wait for the profile host, exactly like the old
        // loader condition did.
        if (root.sharedProfile && root.webProfile === null)
            return null;
        var page = webComponent.createObject(webHost);
        if (!page) return null;
        root.hostedView = page;
        root.hostedView.parent = webHost;
        root.hostedView.anchors.fill = webHost;
        root.hostedView.profile = root.sharedProfile && root.webProfile
            ? root.webProfile : root.isolatedProfile;
        root.hostedView.zoomFactor = root.webZoom;
        root.hostedView.url = root.url;
        return root.hostedView;
    }

    function destroyView() {
        var page = root.hostedView;
        if (!page) return;
        root.hostedView = null;
        page.destroy();
    }

    // The shared profile lives in its host and disappears with it, so the
    // page always follows whichever profile this body would open with.
    function syncViewProfile() {
        if (!root.hostedView) return;
        var next = root.sharedProfile && root.webProfile
            ? root.webProfile : root.isolatedProfile;
        if (root.hostedView.profile !== next) root.hostedView.profile = next;
    }

    // Hand the page over to the picture-in-picture copy. The flag stays set
    // afterwards, so this body cannot start a second copy of the site while
    // the window still owns the page.
    function releaseWebView() {
        var page = root.hostedView;
        root.hostedView = null;
        root.viewReleased = true;
        return page;
    }

    function adoptWebView(v, released) {
        if (!v) return;
        root.hostedView = v;
        root.viewReleased = released;
        root.hostedView.parent = webHost;
        root.hostedView.anchors.fill = webHost;
        root.asleep = false;
        var u = root.hostedView.url ? root.hostedView.url.toString() : "";
        if (u && u !== "about:blank" && u !== root.url) root.url = u;
        if (root.hostedView.zoomFactor !== root.webZoom)
            root.webZoom = root.hostedView.zoomFactor;
        if (root.url !== ""
                && !root.sameUrl(root.hostedView.url.toString(), root.url))
            root.hostedView.url = root.url;
    }

    // Called by the picture-in-picture copy when it receives the page.
    function hostWebView(v) { root.adoptWebView(v, true); }
    // Called when the page comes back to the canvas copy.
    function acceptWebView(v) { root.adoptWebView(v, false); }

    function openUrl() {
        var target = normalize(urlField.text);
        if (target === "") return;
        if (root.app.adblockCheck(target)) {
            root.app.toast("Blocked by the ad blocker");
            return;
        }
        root.url = target;
        root.asleep = false;
        // onUrlChanged above already moved the page when needed; only push
        // again when it is not showing this URL (e.g. the ad-blocker's
        // about:blank), so retyping the current address never reloads it.
        if (root.view && !root.sameUrl(root.view.url.toString(), target))
            root.view.url = target;
        root.persistUrl(target);
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
                objectName: "webBack"
                Layout.alignment: Qt.AlignVCenter
                name: "chevron-left"
                size: root.th.iconBody
                color: root.canGoBack ? root.th.text2 : root.th.muted
                HoverHandler { id: backHover }
                TapHandler { onTapped: if (root.canGoBack) root.view.goBack() }
                ToolTip.visible: backHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Back"
            }
            Icon {
                objectName: "webForward"
                Layout.alignment: Qt.AlignVCenter
                name: "chevron-right"
                size: root.th.iconBody
                color: root.canGoForward ? root.th.text2 : root.th.muted
                HoverHandler { id: forwardHover }
                TapHandler { onTapped: if (root.canGoForward) root.view.goForward() }
                ToolTip.visible: forwardHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Forward"
            }
            Icon {
                objectName: "webReload"
                Layout.alignment: Qt.AlignVCenter
                name: "refresh-cw"
                size: root.th.iconBody
                color: root.th.text2
                HoverHandler { id: reloadHover }
                TapHandler { onTapped: if (root.view) root.view.reload() }
                ToolTip.visible: reloadHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Reload"
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
                objectName: "webZoomOut"
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 500
                name: "zoom-out"
                size: root.th.iconBody
                color: root.th.text2
                HoverHandler { id: zoomOutHover }
                TapHandler { onTapped: root.webZoom = Math.max(0.4, root.webZoom - 0.1) }
                ToolTip.visible: zoomOutHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Zoom out"
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
                objectName: "webZoomIn"
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 500
                name: "zoom-in"
                size: root.th.iconBody
                color: root.th.text2
                HoverHandler { id: zoomInHover }
                TapHandler { onTapped: root.webZoom = Math.min(2.5, root.webZoom + 0.1) }
                ToolTip.visible: zoomInHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Zoom in"
            }
            Icon {
                objectName: "webOpenExternal"
                Layout.alignment: Qt.AlignVCenter
                name: "external-link"
                size: root.th.iconBody
                color: root.th.text2
                HoverHandler { id: externalHover }
                TapHandler { onTapped: root.app.openExternal(root.url) }
                ToolTip.visible: externalHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Open in browser"
            }
            Icon {
                objectName: "webKeepAwake"
                Layout.alignment: Qt.AlignVCenter
                visible: root.width > 400
                name: "coffee"
                size: root.th.iconBody
                color: root.noSleep ? root.th.accent : root.th.muted
                HoverHandler { id: sleepHover }
                TapHandler { onTapped: root.toggleSleep() }
                ToolTip.visible: sleepHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: root.noSleep ? "Allow sleeping to save memory"
                                           : "Keep this card awake"
            }
            Icon {
                objectName: "webSession"
                Layout.alignment: Qt.AlignVCenter
                name: "shield"
                size: root.th.iconBody
                color: root.app.adblockCheck(root.url) ? root.th.accent : root.th.muted
                HoverHandler { id: sessionHover }
                TapHandler { onTapped: debugPopup.open() }
                ToolTip.visible: sessionHover.hovered && root.tooltipsEnabled
                ToolTip.delay: 400
                ToolTip.text: "Website session"
            }
        }

        Item {
            id: webHost
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

            // The page itself is created by ensureView() and then lives in
            // this item until the card hands it to its picture-in-picture
            // copy, so no state of the site is thrown away on the way.
            Component {
                id: webComponent

                WebEngineView {
                }
            }
        }
    }

    // Whoever is hosting the page reacts to its navigation: the canvas copy
    // and the picture-in-picture copy both keep their address bar and their
    // persisted URL up to date, and both run the ad-blocker hooks.
    Connections {
        target: root.view

        function onUrlChanged() {
            var page = root.view;
            if (!page || !root.app || root.blocking) return;
            var nextUrl = page.url.toString();
            if (nextUrl === "" || nextUrl === "about:blank") return;
            if (root.app.adblockCheck(nextUrl)) {
                root.blocking = true;
                root.app.toast("Blocked " + nextUrl);
                page.url = "about:blank";
                root.blocking = false;
                return;
            }
            urlField.text = nextUrl;
            if (root.url !== nextUrl) root.url = nextUrl;
            root.persistUrl(nextUrl);
        }

        function onLoadingChanged(loadRequest) {
            var page = root.view;
            if (!page || !root.app) return;
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                var hosts = root.app.adblockHosts();
                page.runJavaScript(
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
                if (root.view) root.view.runJavaScript("window.__corchoProbe || ''", function (probeResult) {
                    if (probeResult) root.debugOutput = String(probeResult);
                });
            }, 2500);
        });
    }
}
