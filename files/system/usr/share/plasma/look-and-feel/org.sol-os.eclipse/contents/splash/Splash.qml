import QtQuick 2.15

Rectangle {
    id: root
    color: "#080A0F"

    property int stage: 0
    property bool ready: false

    Component.onCompleted: {
        ready = true;
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: root.stage >= 6 ? 0.0 : (root.ready ? 1.0 : 0.0)

        Behavior on opacity {
            NumberAnimation {
                duration: 550
                easing.type: Easing.InOutQuad
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 24

            Item {
                id: emblemContainer
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240
                height: 240

                Image {
                    id: eclipseImage
                    anchors.centerIn: parent
                    width: 204
                    height: 204
                    source: "images/eclipse.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    opacity: root.ready && status === Image.Ready ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 750
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Canvas {
                    id: arcCanvas
                    anchors.centerIn: parent
                    width: 228
                    height: 228
                    antialiasing: true
                    opacity: root.stage >= 5 ? 0.0 : (root.stage >= 2 ? 1.0 : (root.stage >= 1 ? 0.85 : 0.7))

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.InOutQuad
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        var cx = width / 2;
                        var cy = height / 2;
                        var radius = (Math.min(width, height) / 2) - 10;
                        var segments = 48;
                        var startAngle = -Math.PI * 0.85;
                        var sweepAngle = Math.PI * 1.15;

                        for (var i = 0; i < segments; i++) {
                            var t0 = i / segments;
                            var t1 = (i + 1.2) / segments;
                            if (t1 > 1.0) {
                                t1 = 1.0;
                            }
                            var a0 = startAngle + t0 * sweepAngle;
                            var a1 = startAngle + t1 * sweepAngle;
                            var gr = Math.round(74 + (229 - 74) * t0);
                            var gg = Math.round(58 + (181 - 58) * t0);
                            var gb = Math.round(32 + (103 - 32) * t0);
                            var glowAlpha = Math.pow(t0, 1.6) * 0.24;

                            ctx.beginPath();
                            ctx.arc(cx, cy, radius, a0, a1, false);
                            ctx.strokeStyle = "rgba(" + gr + "," + gg + "," + gb + "," + glowAlpha.toFixed(3) + ")";
                            ctx.lineWidth = 7.5;
                            ctx.lineCap = "round";
                            ctx.stroke();
                        }

                        for (var j = 0; j < segments; j++) {
                            var s0 = j / segments;
                            var s1 = (j + 1.2) / segments;
                            if (s1 > 1.0) {
                                s1 = 1.0;
                            }
                            var ang0 = startAngle + s0 * sweepAngle;
                            var ang1 = startAngle + s1 * sweepAngle;
                            var cr = Math.round(74 + (229 - 74) * s0);
                            var cg = Math.round(58 + (181 - 58) * s0);
                            var cb = Math.round(32 + (103 - 32) * s0);
                            var alpha = s0 < 0.15 ? (s0 / 0.15) * 0.35 : (0.35 + ((s0 - 0.15) / 0.85) * 0.65);

                            ctx.beginPath();
                            ctx.arc(cx, cy, radius, ang0, ang1, false);
                            ctx.strokeStyle = "rgba(" + cr + "," + cg + "," + cb + "," + alpha.toFixed(3) + ")";
                            ctx.lineWidth = 2.6;
                            ctx.lineCap = "round";
                            ctx.stroke();
                        }
                    }

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1600
                        loops: Animation.Infinite
                        running: true
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Text {
                    id: titleText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SOL"
                    color: "#E8C992"
                    font.pixelSize: 56
                    font.weight: Font.Light
                    font.letterSpacing: 18
                    leftPadding: 18
                    opacity: root.stage >= 2 ? 1.0 : (root.stage >= 1 ? 0.85 : 0.72)

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.InOutQuad
                        }
                    }
                }

                Text {
                    id: subtitleText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "startup"
                    color: "#B89B6B"
                    font.pixelSize: 18
                    font.weight: Font.Light
                    font.letterSpacing: 5
                    leftPadding: 5
                    opacity: root.stage >= 3 ? 0.95 : (root.stage >= 2 ? 0.82 : 0.60)

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }
    }
}
