pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

StyledRect {
    id: root

    color: Colours.tPalette.m3surfaceContainerLow
    radius: Tokens.rounding.large
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        spacing: 0

        // Column headings, which also sort.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large + scrollBar.width
            Layout.topMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.padding.small
            spacing: Tokens.spacing.medium

            Heading {
                Layout.fillWidth: true
                text: qsTr("Name")
                key: "name"
            }

            Heading {
                Layout.preferredWidth: 72
                horizontalAlignment: Text.AlignRight
                text: qsTr("CPU")
                key: "cpu"
            }

            Heading {
                Layout.preferredWidth: 92
                horizontalAlignment: Text.AlignRight
                text: qsTr("Memory")
                key: "memory"
            }
        }

        StyledListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            model: Processes.model
            spacing: 1

            delegate: ProcessRow {
                width: list.width - scrollBar.width
            }

            // Sorting is damped in the service. Do not animate every displaced
            // delegate on a sample: churn elsewhere in the model would keep
            // the visible list rendering even when its rows did not change.

            StyledScrollBar.vertical: StyledScrollBar {
                id: scrollBar

                flickable: list
            }

            StyledText {
                anchors.centerIn: parent
                visible: list.count === 0 && Processes.active
                text: Processes.query ? qsTr("No process matches “%1”").arg(Processes.query) : qsTr("Reading processes…")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }
    }

    component Heading: StyledText {
        id: heading

        required property string key
        readonly property bool current: Processes.sortKey === key

        font: Tokens.font.label.medium
        color: current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        elide: Text.ElideRight

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Processes.sortKey = heading.key
        }
    }
}
