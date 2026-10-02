pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services
import "unnova.js" as U

RowLayout {
    id: root

    property var runtime: AiRuntime
    readonly property var can: U.aiCan({ installed: runtime.info.installed, serving: runtime.serving, stopping: runtime.stopping, installing: runtime.installing, endpoint: runtime.endpoint })
    spacing: Tokens.spacing.small

    IconTextButton {
        objectName: "aiStartStop"
        icon: root.runtime.serving ? "eject" : "play_arrow"
        text: root.runtime.serving ? qsTr("Unload") : qsTr("Start")
        type: IconTextButton.Tonal
        isRound: true
        disabled: root.runtime.serving ? !root.can.unload : !root.can.start
        onClicked: {
            if (root.runtime.serving && root.can.unload)
                root.runtime.stop();
            else if (root.can.start)
                root.runtime.start();
        }
    }

    IconTextButton {
        objectName: "aiRestart"
        icon: "restart_alt"
        text: qsTr("Restart")
        type: IconTextButton.Tonal
        isRound: true
        disabled: !root.can.restart
        onClicked: if (root.can.restart) root.runtime.restart()
    }
}
