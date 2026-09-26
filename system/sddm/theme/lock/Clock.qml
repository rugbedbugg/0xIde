pragma ComponentBehavior: Bound

import QtQuick
import "../components"

// modules/lock/center/Clock.qml: hours in primary, minutes in secondary, both
// in condensed Google Sans Flex, and an AM/PM chip under the minutes when the
// shell uses a twelve-hour clock.
//
// The shell pads the chip by a fixed amount that does not scale with the
// clock, which only fits at the lockscreen's size; here the padding gives way
// to the room left under the minutes, so the chip never runs into them.
Item {
    id: root

    required property real centerScale
    property bool twelveHour
    property date now: new Date()

    // Qt only counts "hh" in twelve hours when the same format has "AP".
    readonly property string hourStr: twelveHour ? Qt.formatTime(now, "hh AP").split(" ")[0] : Qt.formatTime(now, "HH")
    readonly property string minuteStr: Qt.formatTime(now, "mm")
    readonly property string amPmStr: Qt.formatTime(now, "AP")
    // Where the minutes' ink ends and the chip starts, for tests/run.
    readonly property real minutesBottom: minuteMetrics.tightBoundingRect.height
    readonly property real chipTop: chip.y

    function calcTopOff(metrics: TextMetrics): real {
        return metrics.tightBoundingRect.y - metrics.boundingRect.y;
    }

    implicitWidth: hours.implicitWidth + minutes.implicitWidth + Tokens.spacing.small
    implicitHeight: hourMetrics.tightBoundingRect.height

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    StyledText {
        id: hours

        y: -root.calcTopOff(hourMetrics)
        text: root.hourStr
        color: Colours.palette.m3primary
        font.pointSize: Tokens.font.headlineLarge * 7 * root.centerScale
        font.weight: Font.Medium
        font.variableAxes: ({ "ROND": 25, "wdth": 30 })

        TextMetrics {
            id: hourMetrics

            text: hours.text
            font: hours.font
        }
    }

    StyledText {
        id: minutes

        anchors.right: parent.right
        y: -root.calcTopOff(minuteMetrics)

        text: root.minuteStr
        color: Colours.palette.m3secondary
        font.pointSize: Tokens.font.headlineLarge * (root.twelveHour ? 3.8 : 7) * root.centerScale
        font.weight: Font.Medium
        font.variableAxes: ({ "ROND": 25, "wdth": 30 })

        TextMetrics {
            id: minuteMetrics

            text: minutes.text
            font: minutes.font
        }
    }

    StyledRect {
        id: chip

        anchors.left: minutes.left
        anchors.leftMargin: minuteMetrics.tightBoundingRect.x
        y: hourMetrics.tightBoundingRect.height - height

        visible: root.twelveHour
        color: Colours.surface(Colours.palette.m3surfaceContainerHigh, "clock")
        radius: Math.min(Tokens.rounding.large, height / 2)

        implicitWidth: minuteMetrics.tightBoundingRect.width
        implicitHeight: {
            const room = hourMetrics.tightBoundingRect.height - minuteMetrics.tightBoundingRect.height - Tokens.spacing.small * root.centerScale * 2;
            const text = amPmMetrics.tightBoundingRect.height;
            return Math.min(text + Tokens.padding.large * 2, Math.max(text + Tokens.padding.extraSmall * 2, room));
        }

        // Hyprland's blur behind a translucent surface; see Frost.
        Frost {
            anchors.fill: parent
            z: -1
            surface: "clock"
            radius: chip.radius
        }

        StyledText {
            id: amPm

            anchors.centerIn: parent
            width: amPmMetrics.tightBoundingRect.width
            height: amPmMetrics.tightBoundingRect.height
            transform: Translate {
                x: -amPmMetrics.tightBoundingRect.x
                y: -root.calcTopOff(amPmMetrics)
            }

            text: root.amPmStr
            color: Colours.palette.m3onSurface
            font.pointSize: 24 * 2 * root.centerScale
            font.weight: Font.Medium
            font.variableAxes: ({ "ROND": 25, "wdth": 30 })

            TextMetrics {
                id: amPmMetrics

                text: amPm.text
                font: amPm.font
            }
        }
    }
}
