pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// UnNova, the system monitor, as a window the shell owns, the way Nexus is.
// There is never more than one: opening it while it is open brings it forward.
// Processes are sampled only while the window exists, through its ServiceRef.
Singleton {
    id: root

    property QtObject window: null
    readonly property bool isOpen: window !== null

    function open(): void {
        if (window) {
            focus();
            return;
        }
        window = windowComp.createObject(holder);
    }

    function close(): void {
        window?.destroy();
    }

    function focus(): void {
        const shell = Quickshell.processId;
        const top = Hypr.toplevels.values.find(t => t.title === "UnNova" && (t.lastIpcObject?.pid ?? shell) === shell);
        if (top)
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${top.address}" })` : `focuswindow address:0x${top.address}`);
    }

    QtObject {
        id: holder
    }

    Component {
        id: windowComp

        FloatingWindow {
            id: win

            title: "UnNova"
            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            implicitWidth: Math.round((screen?.width ?? 1920) * 0.62)
            implicitHeight: Math.round((screen?.height ?? 1080) * 0.72)
            minimumSize.width: 880
            minimumSize.height: 560

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            onVisibleChanged: {
                if (!visible)
                    destroy();
            }
            Component.onDestruction: {
                if (root.window === win)
                    root.window = null;
            }

            ServiceRef {
                service: Processes
            }

            Content {
                anchors.fill: parent
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
