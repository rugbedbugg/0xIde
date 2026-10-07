pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import "unnova.js" as U

// One process. Clicking the row selects it; the chevron, in the tree, only
// folds or unfolds its children. They are separate controls on purpose.
StyledRect {
    id: root

    required property string key
    required property int pid
    required property string name
    required property string user
    required property real cpu
    required property real memory
    required property int depth
    required property bool hasChildren
    required property bool expanded
    required property bool match

    readonly property bool selected: Processes.selectedKey === key
    readonly property real indent: Processes.treeMode ? depth * Tokens.padding.extraLarge : 0

    implicitHeight: row.implicitHeight + Tokens.padding.small * 2
    radius: Tokens.rounding.medium
    color: selected ? Colours.palette.m3secondaryContainer : "transparent"

    StateLayer {
        id: select

        radius: root.radius
        color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        onClicked: Processes.selectedKey = root.key
    }

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.medium + root.indent
        anchors.rightMargin: Tokens.padding.large
        spacing: Tokens.spacing.medium

        Item {
            visible: Processes.treeMode
            implicitWidth: chevron.implicitWidth
            implicitHeight: chevron.implicitHeight

            IconButton {
                id: chevron

                anchors.centerIn: parent
                visible: root.hasChildren
                // While searching, the tree opens whatever a match needs.
                disabled: Processes.query !== ""
                icon: "chevron_right"
                type: IconButton.Text
                label.rotation: root.expanded ? 90 : 0
                onClicked: Processes.toggleExpanded(root.key)

                Behavior on label.rotation {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            opacity: root.match ? 1 : 0.55

            StyledText {
                Layout.fillWidth: true
                text: root.name
                font: Tokens.font.body.medium
                color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: `${root.pid} · ${root.user}`
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }

        StyledText {
            Layout.preferredWidth: 72
            horizontalAlignment: Text.AlignRight
            text: U.formatPercent(root.cpu)
            font: Tokens.font.body.medium
            color: root.cpu >= 50 ? Colours.palette.m3error : root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        }

        StyledText {
            Layout.preferredWidth: 92
            horizontalAlignment: Text.AlignRight
            text: U.formatBytes(root.memory)
            font: Tokens.font.body.medium
            color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        }
    }
}
