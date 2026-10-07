pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

// Desktop profiles as a Nexus page: which one is active, and a confirmed
// switch to each of the others. The profiles and the switching both come from
// 0xIde's command line through DesktopProfiles, as they do for >theme.
PageBase {
    id: root

    title: qsTr("Theme")

    Component.onCompleted: DesktopProfiles.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Desktop")
        }

        InfoRow {
            first: true
            icon: "desktop_windows"
            label: qsTr("Current desktop")
            subtext: {
                if (DesktopProfiles.switching)
                    return qsTr("Switching to %1…").arg(DesktopProfiles.name(DesktopProfiles.switchingTo));
                return DesktopProfiles.active?.description ?? "";
            }
            value: DesktopProfiles.active?.name ?? qsTr("Unknown")
            iconColour: DesktopProfiles.error && !DesktopProfiles.switching ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        }

        // Why the last switch did not happen, in full: InfoRow's subtext is
        // cut to one line.
        ConnectedRect {
            Layout.fillWidth: true
            visible: !!DesktopProfiles.error && !DesktopProfiles.switching
            implicitHeight: switchError.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: switchError

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                wrapMode: Text.Wrap
                color: Colours.palette.m3error
                font: Tokens.font.label.large
                text: qsTr("Not switched: %1").arg(DesktopProfiles.error)
            }
        }

        Repeater {
            // Not offered while a switch runs: the command line would refuse it.
            model: DesktopProfiles.switching ? [] : DesktopProfiles.profiles.filter(p => !p.active)

            DialogRowButton {
                id: row

                required property var modelData

                rootParent: root.flickable
                icon: "swap_horiz"
                label: qsTr("Switch to %1").arg(row.modelData.name)
                header: qsTr("Switch to %1?").arg(row.modelData.name)
                acceptLabel: qsTr("Switch")
                onAccepted: DesktopProfiles.activate(row.modelData.id)

                content: Component {
                    StyledText {
                        wrapMode: Text.Wrap
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        text: qsTr("Your windows are rearranged for %1 and this shell keeps running. If the switch fails, the current desktop is restored.").arg(row.modelData.name)
                    }
                }
            }
        }
    }
}
