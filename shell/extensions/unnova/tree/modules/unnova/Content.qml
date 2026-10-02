pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    // 0: 0xIde, 1: Processes. It opens on the processes, which is what the
    // launcher's tooltip promises.
    property int currentTab: 1

    signal close

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.leftMargin: Tokens.padding.small
                text: "monitoring"
                fill: 1
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
            }

            StyledText {
                text: qsTr("UnNova")
                font: Tokens.font.title.large
            }

            Item {
                Layout.fillWidth: true
            }

            TabBar {
                Layout.preferredWidth: Math.min(420, root.width / 2)
                currentIndex: root.currentTab
                tabs: [
                    {
                        icon: "deployed_code",
                        text: qsTr("0xIde")
                    },
                    {
                        icon: "list_alt",
                        text: qsTr("Processes")
                    }
                ]
                onSelected: index => root.currentTab = index
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                inactiveOnColour: hovered ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                stateLayer.opacity: 0
                onClicked: root.close()
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            OxideTab {}

            ProcessesTab {}
        }
    }
}
