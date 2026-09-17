pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

// Names the action that releasing the mouse will take, next to the pointer.
// The label is shown first and then collapses to the icon alone, so the guide
// stops covering the thing being selected.
Item {
    id: root

    required property string icon
    required property string label

    property bool expanded: true

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Caelestia has animation durations but no token for how long a hint should
    // stay up, so this is the one value with no semantic source. It is the
    // interval Illogical Impulse uses for the same guide.
    Timer {
        id: dwell

        interval: 1000
        running: true
        onTriggered: root.expanded = false
    }

    onLabelChanged: {
        expanded = true;
        dwell.restart();
    }

    Elevation {
        anchors.fill: pill
        radius: pill.radius
        level: 2
    }

    StyledRect {
        id: pill

        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
        clip: true

        implicitHeight: iconLabel.implicitHeight + Tokens.padding.small * 2
        implicitWidth: root.expanded ? iconLabel.implicitWidth + text.implicitWidth + Tokens.spacing.small + Tokens.padding.small * 2 + Tokens.padding.medium : implicitHeight

        Behavior on implicitWidth {
            Anim {
                type: Anim.Emphasized
            }
        }

        MaterialIcon {
            id: iconLabel

            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.small
            anchors.verticalCenter: parent.verticalCenter
            color: Colours.palette.m3onPrimary
            fontStyle: Tokens.font.icon.small
            text: root.icon
        }

        StyledText {
            id: text

            anchors.left: iconLabel.right
            anchors.leftMargin: Tokens.spacing.small
            anchors.verticalCenter: parent.verticalCenter
            color: Colours.palette.m3onPrimary
            font: Tokens.font.label.large
            text: root.label
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }
    }
}
