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

    SurfaceChrome {
        anchors.fill: parent
        onActivated: root.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraLarge
        spacing: Tokens.spacing.large

        TabBar {
            Layout.alignment: Qt.AlignHCenter
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

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            OxideTab {}

            ProcessesTab {}
        }
    }
}
