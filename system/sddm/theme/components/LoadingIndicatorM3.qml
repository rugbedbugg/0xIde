import QtQuick
import M3Shapes

// components/controls/LoadingIndicator.qml from the shell. Its ElapsedTimer
// is a Caelestia type, so elapsed time comes from Date.now() instead.
MaterialShape {
    id: root

    property list<int> shapes: [MaterialShape.SoftBurst, MaterialShape.Cookie9Sided, MaterialShape.Pentagon, MaterialShape.Pill, MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Oval]
    property int shapeIndex
    property real cRotation
    property real lRotation
    property real thisLRotation
    property int morphAnimRotation: 60
    property real morphScale: 0.14
    property real stiffness: 180
    property real dampingRatio: 0.6
    property real visibilityThreshold: 0.075
    property real startedAt
    property bool springSettled: true

    readonly property real springDuration: {
        const wn = Math.sqrt(stiffness);
        const r = -dampingRatio * wn;
        const c = 1 / Math.sqrt(1 - dampingRatio * dampingRatio);
        return Math.log(visibilityThreshold / c) / r;
    }
    readonly property real springMaxVelocity: {
        const z = dampingRatio;
        const wn = Math.sqrt(stiffness);
        return wn * Math.exp(-z * Math.acos(z) / Math.sqrt(1 - z * z));
    }

    function spring(t: real): var {
        const wn = Math.sqrt(stiffness);
        const za = dampingRatio * wn;
        const wd = wn * Math.sqrt(1 - dampingRatio * dampingRatio);
        const r = za / wd;
        const pos = 1 - Math.exp(-za * t) * (Math.cos(wd * t) + r * Math.sin(wd * t));
        const vel = Math.exp(-za * t) * (wn * wn / wd) * Math.sin(wd * t);
        return [pos, vel];
    }

    anchors.fill: parent
    implicitSize: Math.min(width, height)
    toShape: shapes[0]

    FrameAnimation {
        running: !root.springSettled
        onTriggered: {
            const t = (Date.now() - root.startedAt) / 1000;
            if (t >= root.springDuration) {
                root.springSettled = true;
            } else {
                const [pos, vel] = root.spring(t);
                root.morphProgress = Math.min(1, pos); // Overshooting the morph looks wrong
                root.thisLRotation = pos * root.morphAnimRotation;
                root.scale = 1 + vel * root.morphScale / root.springMaxVelocity;
            }
        }
    }

    Timer {
        interval: 650
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: {
            root.beginBatchUpdate();
            root.fromShape = root.toShape;
            root.shapeIndex = (root.shapeIndex + 1) % root.shapes.length;
            root.toShape = root.shapes[root.shapeIndex];
            root.morphProgress = 0;
            root.lRotation = (root.lRotation + root.thisLRotation) % 360;
            root.thisLRotation = 0;
            root.rotation = Qt.binding(() => root.cRotation + root.lRotation + root.thisLRotation);
            root.springSettled = false;
            root.startedAt = Date.now();
            root.endBatchUpdate();
        }
    }

    RotationAnimation on cRotation {
        from: 0
        to: 360
        easing.type: Easing.Linear
        loops: Animation.Infinite
        duration: 4666
    }
}
