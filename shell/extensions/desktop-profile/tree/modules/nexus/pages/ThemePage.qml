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
            subtext: DesktopProfiles.active?.description ?? ""
            value: DesktopProfiles.active?.name ?? qsTr("Unknown")
        }

        Repeater {
            model: DesktopProfiles.profiles.filter(p => !p.active)

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
                        text: qsTr("This shell closes and %1 takes over the desktop. If it does not start, the current desktop comes back.").arg(row.modelData.name)
                    }
                }
            }
        }
    }
}
