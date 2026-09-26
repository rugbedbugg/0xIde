import QtQuick
import "../components"

// components/controls/IconButton.qml as a Filled toggle: (t)surfaceContainer and onSurfaceVariant at rest, primary and onPrimary with
// the filled symbol while its menu is open, and ButtonBase's rounding, which
// tightens under a press and settles at medium while checked.
StyledRect {
    id: root

    required property string icon
    required property real scaleFactor
    property bool checked

    signal clicked

    implicitWidth: implicitHeight
    implicitHeight: {
        const h = Math.round(52 * scaleFactor);
        return h % 2 === 0 ? h : h + 1;
    }

    radius: stateLayer.pressed ? Tokens.rounding.small : checked ? Tokens.rounding.medium : Tokens.rounding.large
    color: checked ? Colours.palette.m3primary : Colours.surface(Colours.palette.m3surfaceContainer, "buttons")

    Behavior on radius {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    // Hyprland's blur behind a translucent surface; see Frost.
    Frost {
        anchors.fill: parent
        z: -1
        surface: "buttons"
        radius: root.radius
    }

    StateLayer {
        id: stateLayer

        color: root.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
        onClicked: root.clicked()
    }

    MaterialIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: root.icon
        fill: root.checked ? 1 : 0
        color: root.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
        size: Math.round(Tokens.font.iconLarge * root.scaleFactor)

        Behavior on fill {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
