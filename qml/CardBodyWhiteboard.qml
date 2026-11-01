import QtQuick

CardFrame {
    id: root

    property var strokes: (card.strokes) ? card.strokes : []
    property string penColor: (card.penColor) ? card.penColor : "#e0a48f"
    property real penWidth: (card.penWidth) ? card.penWidth : 3
    property var current: []
    property bool drawing: false

    function persist() {
        root.commit({ strokes: root.strokes, penColor: root.penColor, penWidth: root.penWidth });
    }

    onStrokesChanged: canvas.requestPaint()

    Column {
        anchors.fill: parent
        spacing: 6

        Row {
            spacing: 6

            Repeater {
                model: ["#e0a48f", "#e8e8ea", "#86b78a", "#7aa2f7", "#e07a7a"]

                delegate: Item {
                    required property var modelData
                    width: 16
                    height: 16

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: modelData
                        border.width: root.penColor === modelData ? 2 : 0
                        border.color: root.th.text
                    }
                    TapHandler {
                        onTapped: {
                            root.penColor = modelData;
                            root.persist();
                        }
                    }
                }
            }

            Item { width: 6; height: 1 }

            Icon {
                name: "trash-2"
                size: 14
                color: root.th.muted
                TapHandler {
                    onTapped: {
                        root.strokes = [];
                        root.persist();
                        canvas.requestPaint();
                    }
                }
            }
        }

        Canvas {
            id: canvas
            width: parent.width
            height: parent.height - 26
            renderStrategy: Canvas.Cooperative

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                for (var i = 0; i < root.strokes.length; i++) {
                    var s = root.strokes[i];
                    if (!s.points || s.points.length < 2) continue;
                    ctx.strokeStyle = s.color || root.penColor;
                    ctx.lineWidth = s.width || root.penWidth;
                    ctx.beginPath();
                    ctx.moveTo(s.points[0].x, s.points[0].y);
                    for (var j = 1; j < s.points.length; j++) ctx.lineTo(s.points[j].x, s.points[j].y);
                    ctx.stroke();
                }
                if (root.current.length > 1) {
                    ctx.strokeStyle = root.penColor;
                    ctx.lineWidth = root.penWidth;
                    ctx.beginPath();
                    ctx.moveTo(root.current[0].x, root.current[0].y);
                    for (var k = 1; k < root.current.length; k++) ctx.lineTo(root.current[k].x, root.current[k].y);
                    ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: function (mouse) {
                    root.current = [{ x: mouse.x, y: mouse.y }];
                    root.drawing = true;
                }
                onPositionChanged: function (mouse) {
                    if (!root.drawing) return;
                    root.current.push({ x: mouse.x, y: mouse.y });
                    canvas.requestPaint();
                }
                onReleased: {
                    if (!root.drawing) return;
                    root.drawing = false;
                    if (root.current.length > 1) {
                        var next = root.strokes.slice();
                        next.push({ color: root.penColor, width: root.penWidth, points: root.current });
                        root.strokes = next;
                        root.current = [];
                        root.persist();
                    } else {
                        root.current = [];
                    }
                    canvas.requestPaint();
                }
            }
        }
    }
}
