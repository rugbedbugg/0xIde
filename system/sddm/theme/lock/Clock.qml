pragma ComponentBehavior: Bound

import QtQuick
import "../components"

// modules/lock/center/Clock.qml: hours in primary, minutes in secondary, both
// in condensed Google Sans Flex, and an AM/PM chip under the minutes when the
// shell uses a twelve-hour clock.
Item {
    id: root

    required property real centerScale
    property bool twelveHour
    property date now: new Date()

    // Qt only counts "hh" in twelve hours when the same format has "AP".
    readonly property string hourStr: twelveHour ? Qt.formatTime(now, "hh AP").split(" ")[0] : Qt.formatTime(now, "HH")
    readonly property string minuteStr: Qt.formatTime(now, "mm")
    readonly property string amPmStr: Qt.formatTime(now, "AP")

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
        anchors.left: minutes.left
        anchors.leftMargin: minuteMetrics.tightBoundingRect.x
        y: hourMetrics.tightBoundingRect.height - height

        visible: root.twelveHour
        color: Colours.palette.m3surfaceContainerHigh
        radius: Tokens.rounding.large

        implicitWidth: minuteMetrics.tightBoundingRect.width
        implicitHeight: amPmMetrics.tightBoundingRect.height + Tokens.padding.large * 2

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
