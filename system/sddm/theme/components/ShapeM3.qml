import QtQuick
import M3Shapes

MaterialShape {
    property string shapeName: "Circle"

    anchors.fill: parent
    implicitSize: Math.min(width, height)
    shape: MaterialShape[shapeName] ?? MaterialShape.Circle
    animationDuration: Tokens.anim.durations.expressiveDefaultSpatial
}
