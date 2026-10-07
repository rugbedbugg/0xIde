pragma Singleton

import ".."
import QtQuick
import Quickshell
import Caelestia.Config
import qs.services
import qs.utils

// >theme: 0xIde's desktop profiles as launcher entries, drawn by the
// launcher's own action item.
Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}theme `.length);
    }

    list: variants.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.actions

    Variants {
        id: variants

        model: DesktopProfiles.profiles

        Profile {}
    }

    component Profile: QtObject {
        required property var modelData
        readonly property string name: modelData.name
        readonly property string desc: DesktopProfiles.switchingTo === modelData.id ? qsTr("Switching…") : modelData.active ? qsTr("Current desktop") : modelData.description
        readonly property string icon: modelData.active ? "check_circle" : "desktop_windows"

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            DesktopProfiles.activate(modelData.id);
        }
    }
}
