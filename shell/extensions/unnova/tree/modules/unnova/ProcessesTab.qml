pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

RowLayout {
    id: root

    spacing: Tokens.spacing.large
    readonly property real contentPaneWidth: processPane.width

    ProcessInfo {
        Layout.preferredWidth: Math.max(260, Math.round((root.width - root.spacing) * 0.30))
        Layout.fillHeight: true
    }

    ColumnLayout {
        id: processPane

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Tokens.spacing.medium

        ResourceStrip {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            SearchBar {
                id: search

                Layout.fillWidth: true
                placeholderText: qsTr("Search by name, PID, command or user")
                topPadding: Tokens.padding.medium
                bottomPadding: Tokens.padding.medium
                onTextChanged: Processes.query = text
                Keys.onEscapePressed: clear()
                Component.onCompleted: text = Processes.query
            }

            IconTextButton {
                id: sortButton

                readonly property var labels: ({
                        memory: qsTr("Memory"),
                        cpu: qsTr("CPU"),
                        name: qsTr("Name"),
                        pid: qsTr("PID")
                    })

                icon: "sort"
                text: labels[Processes.sortKey] ?? ""
                type: IconTextButton.Tonal
                isRound: true
                verticalPadding: Tokens.padding.medium
                horizontalPadding: Tokens.padding.large
                onClicked: sortMenu.expanded = !sortMenu.expanded
            }

            ButtonRow {
                spacing: Tokens.spacing.extraSmall

                IconTextButton {
                    icon: "view_list"
                    text: qsTr("List")
                    checked: !Processes.treeMode
                    type: IconTextButton.Tonal
                    verticalPadding: Tokens.padding.medium
                    horizontalPadding: Tokens.padding.large
                    onClicked: Processes.treeMode = false
                }

                IconTextButton {
                    icon: "account_tree"
                    text: qsTr("Tree")
                    checked: Processes.treeMode
                    type: IconTextButton.Tonal
                    verticalPadding: Tokens.padding.medium
                    horizontalPadding: Tokens.padding.large
                    onClicked: Processes.treeMode = true
                }
            }
        }

        ProcessList {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    property Menu sortPopup: Menu {
        id: sortMenu

        parent: root.QsWindow.window?.contentItem ?? null
        attachTo: sortButton
        marginY: Tokens.spacing.small
        active: items.find(i => i.key === Processes.sortKey) ?? null

        items: [
            SortItem {
                key: "memory"
                text: qsTr("Memory")
                icon: "memory_alt"
            },
            SortItem {
                key: "cpu"
                text: qsTr("CPU")
                icon: "memory"
            },
            SortItem {
                key: "name"
                text: qsTr("Name")
                icon: "sort_by_alpha"
            },
            SortItem {
                key: "pid"
                text: qsTr("PID")
                icon: "tag"
            }
        ]
    }

    component SortItem: MenuItem {
        required property string key

        onClicked: Processes.sortKey = key
    }
}
