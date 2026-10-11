pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// The local model installer as AiRuntime reports it, so the area picker and
// Nexus show the same thing. It starts and stops nothing.
InstallProgress {
    runtime: AiRuntime
    what: qsTr("Local model")
    installedHint: GlobalConfig.ai.backend === "managed" ? "" : qsTr("Select the Local backend to use this model")
    notes: ({
            build: qsTr("Build continues after closing this panel"),
            waiting: qsTr("Waiting for the installer or model to finish")
        })
}
