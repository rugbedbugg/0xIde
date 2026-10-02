pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services
import "windowGeometry.js" as Geometry

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

            // ShellScreen dimensions and Hyprland's reserved edges are logical
            // pixels; do not apply the physical monitor scale a second time.
            readonly property var reserved: Hypr.monitorFor(screen)?.lastIpcObject?.reserved ?? []
            readonly property var sizing: Geometry.sizing(screen?.width ?? 1920, screen?.height ?? 1080, reserved)

            implicitWidth: sizing.width.preferred
            implicitHeight: sizing.height.preferred
            minimumSize.width: sizing.width.minimum
            minimumSize.height: sizing.height.minimum
            maximumSize.width: sizing.width.maximum
            maximumSize.height: sizing.height.maximum

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
