pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// The dashboard's tabs, as a row the window owns: icon over label, the current
// one in primary, and an indicator that slides between them.
Item {
    id: root

    required property var tabs
    property int currentIndex

    signal selected(index: int)

    implicitHeight: row.implicitHeight + indicator.anchors.topMargin + indicator.implicitHeight

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Repeater {
            id: repeater

            model: root.tabs

            Item {
                id: tab

                required property int index
                required property var modelData
                readonly property bool current: index === root.currentIndex

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: icon.implicitHeight + label.implicitHeight + Tokens.padding.small * 2

                StateLayer {
                    radius: Tokens.rounding.medium
                    color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    onClicked: root.selected(tab.index)
                }

                MaterialIcon {
                    id: icon

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: label.top
                    text: tab.modelData.icon
                    color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fill: tab.current ? 1 : 0
                    fontStyle: Tokens.font.icon.medium

                    Behavior on fill {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                StyledText {
                    id: label

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Tokens.padding.small
                    text: tab.modelData.text
                    color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Item {
        id: indicator

        readonly property real slot: root.width / Math.max(1, repeater.count)

        anchors.top: row.bottom
        anchors.topMargin: 2
        implicitWidth: slot * 0.5
        implicitHeight: 3
        x: slot * root.currentIndex + (slot - implicitWidth) / 2
        clip: true

        StyledRect {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight * 2
            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
        }

        Behavior on x {
            Anim {}
        }
    }
}
