pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import "unnova.js" as U

// The dashboard's resource gauges, small and in a row: enough to see how the
// machine is doing while reading the list, not a second Performance page.
StyledRect {
    id: root

    readonly property bool compact: width < 800

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large
    implicitHeight: row.implicitHeight + Tokens.padding.medium * 2

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    GridLayout {
        id: row

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        columns: root.compact ? 4 : 6
        columnSpacing: root.compact ? Tokens.spacing.small : Tokens.spacing.large
        rowSpacing: Tokens.spacing.small

        Gauge {
            icon: "memory"
            label: qsTr("CPU")
            value: Cpu.percentage
            detail: U.formatPercent(Cpu.percentage * 100)
        }

        Gauge {
            icon: "memory_alt"
            label: qsTr("Memory")
            value: Memory.percentage
            accent: Colours.palette.m3tertiary
            detail: `${U.formatBytes(Memory.used * 1024)} / ${U.formatBytes(Memory.total * 1024)}`
        }

        Gauge {
            icon: "swap_horiz"
            label: qsTr("Swap")
            value: Processes.swapTotal > 0 ? Processes.swapUsed / Processes.swapTotal : 0
            accent: Colours.palette.m3secondary
            detail: Processes.swapTotal > 0 ? `${U.formatBytes(Processes.swapUsed)} / ${U.formatBytes(Processes.swapTotal)}` : qsTr("None")
        }

        Gauge {
            icon: "hard_disk"
            label: qsTr("Storage")
            value: Storage.percentage
            accent: Colours.palette.m3secondary
            detail: U.formatPercent(Storage.percentage * 100)
        }

        Item {
            Layout.fillWidth: true
            visible: !root.compact
        }

        ColumnLayout {
            Layout.columnSpan: root.compact ? 4 : 1
            Layout.alignment: Qt.AlignRight
            spacing: 0

            StyledText {
                Layout.alignment: Qt.AlignRight
                text: Processes.count
                font: Tokens.font.title.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignRight
                text: qsTr("processes · %1 threads").arg(Processes.threadCount)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    component Gauge: RowLayout {
        id: gauge

        required property string icon
        required property string label
        required property real value
        required property string detail
        property color accent: Colours.palette.m3primary

        spacing: Tokens.spacing.small

        CircularProgress {
            implicitSize: 44
            strokeWidth: Tokens.sizes.dashboard.resourceProgressThickness
            value: gauge.value
            fgColour: gauge.accent

            MaterialIcon {
                anchors.centerIn: parent
                text: gauge.icon
                color: gauge.accent
                fontStyle: Tokens.font.icon.small
            }
        }

        ColumnLayout {
            spacing: 0

            StyledText {
                text: gauge.label
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                text: gauge.detail
                font: Tokens.font.body.small
            }
        }
    }
}
