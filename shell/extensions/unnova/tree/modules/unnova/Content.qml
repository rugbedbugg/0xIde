pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components

Item {
    id: root

    // 0: 0xIde, 1: Processes. The selection belongs to this window only.
    property alias currentTab: tabs.currentIndex

    signal close

    SurfaceChrome {
        id: chrome

        anchors.fill: parent
        z: 1
        onActivated: root.close()
    }

    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large
        implicitHeight: tabs.implicitHeight + Tokens.padding.large

        StyledText {
            id: heading

            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.large
            anchors.right: tabs.left
            anchors.rightMargin: Tokens.spacing.extraLarge
            anchors.verticalCenter: parent.verticalCenter
            text: tabs.tabs[root.currentTab].text
            // The Nexus page heading, without application branding.
            font: Tokens.font.title.large
            elide: Text.ElideRight
        }

        TabBar {
            id: tabs

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: processes.contentPaneWidth
            tabRightInset: Math.max(0, chrome.cornerWidth + Tokens.spacing.large - header.anchors.rightMargin)

            tabs: [
                {
                    iconName: "deployed_code",
                    text: qsTr("0xIde")
                },
                {
                    iconName: "list_alt",
                    text: qsTr("Processes")
                }
            ]
        }
    }

    StackLayout {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        currentIndex: root.currentTab

        OxideTab {}

        ProcessesTab {
            id: processes
        }
    }
}
