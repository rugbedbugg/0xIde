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
    installedHint: GlobalConfig.ai.backend === "managed" ? "" : qsTr("Choose Local as the backend to use it.")
    notes: ({
            build: qsTr("Compiling takes several minutes. It carries on if you close this."),
            waiting: qsTr("Another installation or the running model holds the lock")
        })
}
