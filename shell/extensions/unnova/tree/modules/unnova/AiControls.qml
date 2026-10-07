pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services
import "unnova.js" as U

// The local AI's lifecycle, through AiRuntime's own calls. Only what can be
// done right now is shown: Start when a model is installed and stopped, Unload
// and Restart while it runs, Cancel while it installs. Nothing greyed out
// stands for an action that is not there. Setting up a model is in Settings.
RowLayout {
    id: root

    property var runtime: AiRuntime
    readonly property var can: U.aiCan({ installed: runtime.info.installed, serving: runtime.serving, stopping: runtime.stopping, installing: runtime.installing, endpoint: runtime.endpoint })

    spacing: Tokens.spacing.small

    IconTextButton {
        objectName: "aiStart"
        visible: root.can.start
        icon: "play_arrow"
        text: qsTr("Start")
        type: IconTextButton.Tonal
        isRound: true
        // Checked again: a click can arrive just after the state changed.
        onClicked: if (root.can.start) root.runtime.start()
    }
    IconTextButton {
        objectName: "aiUnload"
        visible: root.can.unload
        icon: "eject"
        text: qsTr("Unload")
        type: IconTextButton.Tonal
        isRound: true
        onClicked: if (root.can.unload) root.runtime.stop()
    }
    IconTextButton {
        objectName: "aiRestart"
        visible: root.can.restart
        icon: "restart_alt"
        text: qsTr("Restart")
        type: IconTextButton.Tonal
        isRound: true
        onClicked: if (root.can.restart) root.runtime.restart()
    }
    IconTextButton {
        objectName: "aiCancel"
        visible: root.runtime.installing && root.runtime.operation !== "uninstall"
        icon: "close"
        text: qsTr("Cancel installation")
        type: IconTextButton.Tonal
        isRound: true
        onClicked: if (root.runtime.installing) root.runtime.cancel()
    }
}
