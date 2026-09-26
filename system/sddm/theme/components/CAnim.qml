import QtQuick

ColorAnimation {
    duration: Tokens.anim.durations.expressiveSlowEffects
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Tokens.anim.expressiveSlowEffects
}
