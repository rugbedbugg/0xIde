import QtQuick
import QtQuick.Effects

// components/StateLayer.qml from the shell: an 8% hover tint and a ripple that
// grows from the press point and fades, clipped to the parent's rounding.
MouseArea {
    id: root

    property bool disabled
    property color color: Colours.palette.m3onSurface
    property real radius: parent?.radius ?? 0
    property real pressX: width / 2
    property real pressY: height / 2
    property real circleRadius
    readonly property real endRadius: {
        const d = Math.max((pressX) ** 2 + (pressY) ** 2, (width - pressX) ** 2 + pressY ** 2, pressX ** 2 + (height - pressY) ** 2, (width - pressX) ** 2 + (height - pressY) ** 2);
        return Math.sqrt(d) * 1.3;
    }

    anchors.fill: parent
    enabled: !disabled
    cursorShape: disabled ? undefined : Qt.PointingHandCursor
    hoverEnabled: true

    onPressed: e => {
        pressX = e.x;
        pressY = e.y;
        fadeAnim.stop();
        circleRadius = 0;
        ripple.opacity = 0.1;
        rippleAnim.restart();
    }
    onReleased: {
        if (!rippleAnim.running)
            fadeAnim.start();
    }

    Anim {
        id: rippleAnim

        target: root
        property: "circleRadius"
        to: root.endRadius
        duration: Tokens.anim.durations.expressiveSlowEffects * 2
        easing.bezierCurve: Tokens.anim.standard
        onFinished: {
            if (!root.pressed)
                fadeAnim.start();
        }
    }

    Anim {
        id: fadeAnim

        target: ripple
        property: "opacity"
        to: 0
        type: Anim.SlowEffects
    }

    Item {
        id: clipper

        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Rectangle {
            anchors.fill: parent
            color: root.color
            opacity: root.containsMouse && !root.disabled ? 0.08 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Rectangle {
            id: ripple

            x: root.pressX - root.circleRadius
            y: root.pressY - root.circleRadius
            width: root.circleRadius * 2
            height: root.circleRadius * 2
            radius: root.circleRadius
            color: root.color
            opacity: 0
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: Math.min(root.radius, width / 2, height / 2)
        visible: false
        layer.enabled: true
    }
}
