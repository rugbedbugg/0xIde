pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"

// The power actions, drawn as the shell's session menu draws them
// (modules/session/Content.qml): square buttons on surfaceContainer whose
// rounding tightens under the pointer's press and opens up on focus, with the
// same symbols. Only the actions SDDM says it can perform are shown.
StyledRect {
    id: root

    implicitHeight: row.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.medium
    color: Colours.palette.m3surfaceContainer

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.medium

        PowerButton {
            visible: sddm.canSuspend
            icon: "bedtime"
            label: qsTr("Suspend")
            onActivated: sddm.suspend()
        }

        PowerButton {
            visible: sddm.canHibernate
            icon: "downloading"
            label: qsTr("Hibernate")
            onActivated: sddm.hibernate()
        }

        PowerButton {
            visible: sddm.canReboot
            icon: "cached"
            label: qsTr("Reboot")
            onActivated: sddm.reboot()
        }

        PowerButton {
            visible: sddm.canPowerOff
            icon: "power_settings_new"
            label: qsTr("Shut down")
            onActivated: sddm.powerOff()
        }
    }

    component PowerButton: StyledRect {
        id: button

        required property string icon
        required property string label
        signal activated

        // Tokens.sizes.session.button is 80; the card is narrower than the
        // session menu, so the buttons scale with it.
        implicitWidth: Math.max(40, Math.min(80, (root.width - Tokens.padding.large * 2 - Tokens.spacing.medium * 3) / 4))
        implicitHeight: implicitWidth
        color: activeFocus ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
        radius: stateLayer.pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
        activeFocusOnTab: true

        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()

        Behavior on radius {
            Anim {
                type: Anim.FastSpatial
            }
        }

        StateLayer {
            id: stateLayer

            onClicked: button.activated()
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: button.icon
            color: button.activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            size: Math.round(Tokens.font.iconLarge * 1.3 * button.implicitWidth / 80)
        }
    }
}
