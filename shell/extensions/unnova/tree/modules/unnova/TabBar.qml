pragma ComponentBehavior: Bound

import Quickshell
import qs.components
import qs.modules.dashboard as Dashboard

// Use the border dropdown's renderer and geometry without sharing its selection.
Dashboard.Tabs {
    id: root

    property alias currentIndex: state.dashboardTab

    nonAnimWidth: width
    screenState: ScreenState {
        id: state

        modelData: root.QsWindow.window?.screen ?? Quickshell.screens[0]
        dashboardTab: 1
    }
}
