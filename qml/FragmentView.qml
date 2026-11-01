import QtQuick

Item {
    id: root

    property string mode: "pop"
    property color accent: "#e0a48f"
    property var th
    property var app
    property bool active: true
    property bool reducedMotion: false
    property real tick: 0

    property var particles: []
    property real pressPulse: 0

    function initParticles() {
        var list = [];
        for (var i = 0; i < 54; i++) {
            list.push({
                x: Math.random(),
                y: Math.random(),
                vx: (Math.random() - 0.5) * 0.0016,
                vy: (Math.random() - 0.5) * 0.0016,
                r: 0.8 + Math.random() * 2.2,
                p: Math.random() * Math.PI * 2
            });
        }
        particles = list;
    }

    function stepParticles() {
        for (var i = 0; i < particles.length; i++) {
            var p = particles[i];
            p.x += p.vx;
            p.y += p.vy;
            if (p.x < 0 || p.x > 1) p.vx *= -1;
            if (p.y < 0 || p.y > 1) p.vy *= -1;
            p.p += 0.03;
        }
    }

    Component.onCompleted: { initParticles(); canvas.requestPaint(); }
    Component.onDestruction: if (mode === "noise") root.app.spectrumStop()

    onModeChanged: {
        if (mode === "noise" && active) root.app.spectrumStart(0.3, 240, 0.45);
        else root.app.spectrumStop();
    }
    onActiveChanged: {
        if (mode === "noise" && active) root.app.spectrumStart(0.3, 240, 0.45);
        else if (mode === "noise") root.app.spectrumStop();
    }

    Timer {
        interval: 33
        repeat: true
        running: root.active && root.visible && !root.reducedMotion
        onTriggered: {
            root.tick += 0.033;
            if (root.mode === "boson") root.stepParticles();
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (width <= 0 || height <= 0) return;
            root.paint(ctx, width, height);
        }

        MouseArea {
            anchors.fill: parent
            onPressed: {
                root.pressPulse = 1.0;
                if (root.mode === "boson") {
                    for (var i = 0; i < root.particles.length; i++) {
                        var p = root.particles[i];
                        var dx = p.x - mouse.x / canvas.width;
                        var dy = p.y - mouse.y / canvas.height;
                        var d = Math.max(0.05, Math.sqrt(dx * dx + dy * dy));
                        p.vx += dx / d * 0.006;
                        p.vy += dy / d * 0.006;
                    }
                }
                canvas.requestPaint();
            }
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.pressPulse > 0
        onTriggered: {
            root.pressPulse = Math.max(0, root.pressPulse - 0.04);
            canvas.requestPaint();
        }
    }

    function paint(ctx, w, h) {
        var a = root.accent;
        var time = root.tick;

        if (mode === "pop") {
            for (var i = 0; i < 5; i++) {
                var phase = (time * 0.5 + i * 0.16) % 1;
                var r = Math.min(w, h) * (0.12 + phase * 0.38);
                ctx.beginPath();
                ctx.arc(w / 2, h / 2, r, 0, Math.PI * 2);
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.28 * (1 - phase) + root.pressPulse * 0.4);
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
            ctx.beginPath();
            ctx.arc(w / 2, h / 2, Math.min(w, h) * (0.08 + root.pressPulse * 0.03), 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.85);
            ctx.fill();
            return;
        }

        if (mode === "gradient") {
            var g1 = ctx.createRadialGradient(
                w * (0.35 + Math.sin(time * 0.4) * 0.12),
                h * (0.4 + Math.cos(time * 0.31) * 0.12),
                2,
                w * 0.5,
                h * 0.5,
                Math.max(w, h) * 0.75
            );
            g1.addColorStop(0, Qt.rgba(a.r, a.g, a.b, 0.6));
            g1.addColorStop(0.5, Qt.rgba(a.r, a.g, a.b, 0.16));
            g1.addColorStop(1, Qt.rgba(a.r, a.g, a.b, 0));
            ctx.fillStyle = g1;
            ctx.fillRect(0, 0, w, h);

            var g2 = ctx.createRadialGradient(
                w * (0.7 + Math.cos(time * 0.27) * 0.1),
                h * (0.66 + Math.sin(time * 0.35) * 0.1),
                1,
                w * 0.5,
                h * 0.5,
                Math.max(w, h) * 0.55
            );
            g2.addColorStop(0, Qt.rgba(1, 1, 1, 0.14));
            g2.addColorStop(1, Qt.rgba(1, 1, 1, 0));
            ctx.fillStyle = g2;
            ctx.fillRect(0, 0, w, h);
            return;
        }

        if (mode === "noise") {
            var bars = 42;
            var bw = w / bars;
            for (var b = 0; b < bars; b++) {
                var n = Math.sin(time * 6 + b * 0.7) * 0.5 + Math.sin(time * 13 + b * 1.9) * 0.3;
                var v = Math.abs(n) * 0.5 + 0.06;
                var bh = v * h * 0.55;
                var alpha = 0.25 + v * 0.7;
                ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, alpha);
                ctx.fillRect(b * bw + bw * 0.24, h / 2 - bh / 2, bw * 0.52, bh);
            }
            ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.5);
            ctx.fillRect(0, h / 2 - 0.5, w, 1);
            return;
        }

        if (mode === "object" || mode === "hypercube") {
            var pts = [];
            var edges = [];
            if (mode === "object") {
                var V = [
                    [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
                    [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]
                ];
                edges = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];
                var ry = time * 0.6, rx = time * 0.37;
                for (var i = 0; i < V.length; i++) {
                    var p = rotate3(V[i], rx, ry);
                    pts.push(project(p, w, h));
                }
            } else {
                var v4 = [];
                for (var m = 0; m < 16; m++) {
                    v4.push([(m & 1) ? 1 : -1, (m & 2) ? 1 : -1, (m & 4) ? 1 : -1, (m & 8) ? 1 : -1]);
                }
                for (var u = 0; u < 16; u++) {
                    for (var bit = 0; bit < 4; bit++) {
                        var v = u ^ (1 << bit);
                        if (u < v) edges.push([u, v]);
                    }
                }
                var r1 = time * 0.5, r2 = time * 0.31;
                for (var k = 0; k < v4.length; k++) {
                    var q = rotate4(v4[k], r1, r2);
                    var scale = 1.3 / (2.4 - q[3]);
                    var p3 = [q[0] * scale, q[1] * scale, q[2] * scale];
                    pts.push(project(p3, w, h));
                }
            }
            var scale2 = Math.min(w, h) * 0.27;
            for (var e = 0; e < edges.length; e++) {
                var A = pts[edges[e][0]], B = pts[edges[e][1]];
                if (!A || !B) continue;
                ctx.beginPath();
                ctx.moveTo(A.x, A.y);
                ctx.lineTo(B.x, B.y);
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, mode === "hypercube" ? 0.35 : 0.55);
                ctx.lineWidth = 1.2;
                ctx.stroke();
            }
            for (var d = 0; d < pts.length; d++) {
                ctx.beginPath();
                ctx.arc(pts[d].x, pts[d].y, 2.2, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.8);
                ctx.fill();
            }
            function rotate3(p, rx, ry) {
                var cy = Math.cos(ry), sy = Math.sin(ry), cx = Math.cos(rx), sx = Math.sin(rx);
                var x = p[0] * cy - p[2] * sy;
                var z = p[0] * sy + p[2] * cy;
                var y = p[1] * cx - z * sx;
                z = p[1] * sx + z * cx;
                return [x, y, z];
            }
            function rotate4(p, r1, r2) {
                var c1 = Math.cos(r1), s1 = Math.sin(r1), c2 = Math.cos(r2), s2 = Math.sin(r2);
                var x = p[0] * c1 - p[3] * s1;
                var w4 = p[0] * s1 + p[3] * c1;
                var y = p[1] * c2 - p[2] * s2;
                var z = p[1] * s2 + p[2] * c2;
                return [x, y, z, w4];
            }
            function project(p, w, h) {
                var s = Math.min(w, h) * 0.27;
                var persp = 2.6 / (2.6 + p[2]);
                return { x: w / 2 + p[0] * s * persp, y: h / 2 + p[1] * s * persp };
            }
            return;
        }

        if (mode === "boson") {
            ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.05);
            ctx.fillRect(0, 0, w, h);
            for (var j = 0; j < particles.length; j++) {
                var pp = particles[j];
                var px = pp.x * w, py = pp.y * h;
                var rr = pp.r * (1 + Math.sin(pp.p) * 0.2);
                ctx.beginPath();
                ctx.arc(px, py, rr, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.25 + Math.abs(Math.sin(pp.p)) * 0.5);
                ctx.fill();
            }
            return;
        }

        if (mode === "vector") {
            var cx = w / 2, cy = h / 2;
            for (var ring = 0; ring < 4; ring++) {
                var radius = Math.min(w, h) * (0.1 + ring * 0.09);
                var start = time * (0.6 - ring * 0.08) + ring;
                ctx.beginPath();
                ctx.arc(cx, cy, radius, start, start + Math.PI * 1.2);
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.2 + ring * 0.16);
                ctx.lineWidth = 2;
                ctx.stroke();
            }
            for (var hand = 0; hand < 3; hand++) {
                var ang = time * (0.8 - hand * 0.22) - Math.PI / 2;
                var len = Math.min(w, h) * (0.32 - hand * 0.07);
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + Math.cos(ang) * len, cy + Math.sin(ang) * len);
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.7);
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
            ctx.beginPath();
            ctx.arc(cx, cy, 3, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.9);
            ctx.fill();
            return;
        }

        if (mode === "calendar") {
            var now = new Date();
            var y = now.getFullYear(), mo = now.getMonth(), day = now.getDate();
            var first = new Date(y, mo, 1).getDay();
            var days = new Date(y, mo + 1, 0).getDate();
            var cols = 7, rows = Math.ceil((first + days) / 7);
            var pad = 12;
            var cw = (w - pad * 2) / cols, ch = (h - pad * 2 - 20) / rows;
            ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.55);
            ctx.font = "500 11px Inter";
            ctx.fillText(now.toLocaleString(Qt.locale(), "MMMM yyyy"), pad, pad + 8);
            for (var dd = 1; dd <= days; dd++) {
                var idx = first + dd - 1;
                var col = idx % 7, row = Math.floor(idx / 7);
                var x = pad + col * cw + cw / 2;
                var yy = pad + 24 + row * ch + ch / 2;
                if (dd === day) {
                    ctx.beginPath();
                    ctx.arc(x, yy, Math.min(cw, ch) * 0.34, 0, Math.PI * 2);
                    ctx.fillStyle = Qt.rgba(a.r, a.g, a.b, 0.85);
                    ctx.fill();
                }
                ctx.fillStyle = dd === day ? root.th.accentInk : Qt.rgba(root.th.text.r, root.th.text.g, root.th.text.b, 0.55);
                ctx.font = "400 10px Inter";
                ctx.textAlign = "center";
                ctx.fillText("" + dd, x, yy + 3);
                ctx.textAlign = "left";
            }
        }
    }
}
