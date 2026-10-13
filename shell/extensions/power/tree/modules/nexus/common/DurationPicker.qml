pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Hours and minutes on two drums, in five-minute steps up to 23 h 55 min.
// Each turns with the wheel or a drag and wraps around; the middle row is the
// value. It holds a duration and says when it changes, and does nothing else.
Item {
    id: root

    // Rounded to five minutes and kept within range on the way in.
    property int minutes
    readonly property int hours: Math.floor(minutes / 60)
    readonly property int minutePart: minutes % 60

    signal picked(int minutes)

    function set(total: int): void {
        const clamped = Math.max(0, Math.min(Math.round(total / 5) * 5, 23 * 60 + 55));
        if (clamped !== minutes) {
            minutes = clamped;
            picked(clamped);
        }
    }

    implicitWidth: row.implicitWidth
    implicitHeight: hoursDrum.implicitHeight

    StyledRect {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: hoursDrum.rowHeight
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainerHigh
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        Drum {
            id: hoursDrum

            values: 24
            value: root.hours
            onPicked: v => root.set(v * 60 + root.minutePart)
        }

        StyledText {
            text: qsTr("h")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }

        Item {
            implicitWidth: Tokens.spacing.large
        }

        Drum {
            values: 12
            step: 5
            value: root.minutePart
            onPicked: v => root.set(root.hours * 60 + v)
        }

        StyledText {
            text: qsTr("min")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }
    }

    component Drum: PathView {
        id: drum

        property int values
        property int step: 1
        property int value
        readonly property real rowHeight: Math.ceil(metrics.height * 1.6)

        signal picked(int value)

        implicitWidth: Math.ceil(metrics.width) + Tokens.padding.large * 2
        implicitHeight: rowHeight * 3
        clip: true

        model: values
        pathItemCount: 5
        preferredHighlightBegin: 0.5
        preferredHighlightEnd: 0.5
        highlightRangeMode: PathView.StrictlyEnforceRange
        highlightMoveDuration: Tokens.anim.durations.normal
        snapMode: PathView.SnapToItem
        dragMargin: width

        path: Path {
            startX: drum.width / 2
            startY: -drum.rowHeight

            PathLine {
                x: drum.width / 2
                y: drum.rowHeight * 4
            }
        }

        delegate: StyledText {
            required property int index

            width: drum.width
            height: drum.rowHeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: String(index * drum.step).padStart(2, "0")
            font: Tokens.font.title.medium
            color: PathView.isCurrentItem ? Colours.palette.m3onSurface : Colours.palette.m3outline
        }

        Component.onCompleted: currentIndex = Math.round(value / step)
        onValueChanged: {
            if (Math.round(value / step) !== currentIndex)
                currentIndex = Math.round(value / step);
        }
        onCurrentIndexChanged: {
            if (currentIndex * step !== value)
                picked(currentIndex * step);
        }

        TextMetrics {
            id: metrics

            font: Tokens.font.title.medium
            text: "00"
        }

        WheelHandler {
            property real pending

            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                pending += event.angleDelta.y;
                while (pending >= 120) {
                    drum.decrementCurrentIndex();
                    pending -= 120;
                }
                while (pending <= -120) {
                    drum.incrementCurrentIndex();
                    pending += 120;
                }
            }
        }
    }
}
