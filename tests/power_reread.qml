//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.nexus
import qs.modules.nexus.pages

// A new shell on the shell.json tests/power_page.qml left: what it chose last
// (sleep off, beside a lock entry) is what this one starts with.
ShellRoot {
    id: h

    settings.watchFiles: false

    readonly property var page: pageLoader.item

    NexusState {
        id: testState
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 900

        Loader {
            id: pageLoader

            anchors.fill: parent
            active: false

            sourceComponent: PowerPage {
                nState: testState
            }
        }
    }

    Timer {
        interval: 200
        running: true
        onTriggered: pageLoader.active = true
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: {
            const list = JSON.parse(JSON.stringify(GlobalConfig.general.idle.timeouts));
            console.log("RESULT " + JSON.stringify({
                restartShowsNever: h.page?.activeItem?.text === "Never" && h.page?.policy.state === "single",
                restartKeepsTheList: list.length === 2 && list[0].idleAction === "lock" && list[0].timeout === 180
                    && list[1].timeout === 7200 && list[1].enabled === false
            }));
            Qt.quit();
        }
    }
}
