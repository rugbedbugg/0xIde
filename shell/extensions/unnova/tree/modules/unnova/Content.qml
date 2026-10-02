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
        anchors.fill: parent
        z: 1 // Keep the corner control above the full-width navigation hit area.
        onActivated: root.close()
    }

    TabBar {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

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

    StackLayout {
        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        currentIndex: root.currentTab

        OxideTab {}

        ProcessesTab {}
    }
}
