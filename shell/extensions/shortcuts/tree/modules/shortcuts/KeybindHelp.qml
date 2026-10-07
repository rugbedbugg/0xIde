pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.components.misc
import qs.services

// Keyboard shortcuts: the keybinds Hyprland has registered right now, on the
// focused screen. Opened by the shortcuts global shortcut (kbShowShortcuts in
// hypr-vars.lua), the "Keyboard Shortcuts" launcher entry, or
// `caelestia shell shortcuts toggle`; closed by the same, Esc, or a click
// outside. View only. While closed there is no window and nothing runs.
Scope {
    id: root

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "shortcuts"
        description: "Toggle keyboard shortcuts"
        onPressed: Keybinds.toggle()
    }

    IpcHandler {
        function toggle(): void {
            Keybinds.toggle();
        }

        function open(): void {
            if (!Keybinds.open)
                Keybinds.show();
        }

        function close(): void {
            Keybinds.hide();
        }

        target: "shortcuts"
    }

    LazyLoader {
        active: Keybinds.open

        StyledWindow {
            id: win

            screen: Quickshell.screens.find(s => Hypr.monitorFor(s) === Hypr.focusedMonitor) ?? Quickshell.screens[0]
            name: "shortcuts"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // A click anywhere but the card closes it, as the drawers do.
            MouseArea {
                anchors.fill: parent
                onClicked: Keybinds.hide()
            }

            Elevation {
                anchors.fill: card
                radius: card.radius
                level: 3
                opacity: card.opacity
            }

            StyledRect {
                id: card

                anchors.centerIn: parent
                // Reference, not a control centre: about half a wide screen,
                // most of a narrow one. The height does not follow the list:
                // a list as tall as its content builds every row at once,
                // which held the shell for seconds, and a fixed size does not
                // jump about while a search narrows it.
                width: Math.min(parent.width - Tokens.padding.extraLarge * 2, Math.max(560, parent.width * 0.48))
                height: Math.min(parent.height - Tokens.padding.extraLarge * 2, Math.max(420, parent.height * 0.72))
                radius: Tokens.rounding.large
                // Opaque: it is read over whatever windows are open, and no
                // layer rule blurs behind this namespace.
                color: Colours.palette.m3surface
                focus: true

                opacity: 0
                scale: 0.97
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                    search.forceActiveFocus();
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                // Clicks on the card stay on the card.
                MouseArea {
                    anchors.fill: parent
                }

                Keys.onEscapePressed: Keybinds.hide()

                ColumnLayout {
                    id: layout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: qsTr("Keyboard shortcuts")
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (!Keybinds.query)
                                        return qsTr("Bound in Hyprland right now");
                                    return Keybinds.matches === 1 ? qsTr("1 match") : qsTr("%1 matches").arg(Keybinds.matches);
                                }
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }

                        SearchBar {
                            id: search

                            Layout.preferredWidth: Math.min(320, card.width * 0.42)
                            placeholderText: qsTr("Search shortcuts")
                            onTextChanged: Keybinds.query = text
                            Keys.onEscapePressed: Keybinds.hide()
                            Keys.onDownPressed: list.flick(0, -1500)
                            Keys.onUpPressed: list.flick(0, 1500)
                        }

                        IconButton {
                            icon: "refresh"
                            type: IconButton.Text
                            enabled: !Keybinds.loading
                            onClicked: Keybinds.refresh()
                        }
                    }

                    // The binds are shown either way; this says why many read
                    // only "Lua action", instead of guessing what they do.
                    StyledRect {
                        objectName: "unannotatedBanner"
                        Layout.fillWidth: true
                        visible: !Keybinds.annotated && !Keybinds.loading && !Keybinds.error && Keybinds.binds.length > 0
                        implicitHeight: bannerText.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3secondaryContainer

                        StyledText {
                            id: bannerText

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            wrapMode: Text.Wrap
                            color: Colours.palette.m3onSecondaryContainer
                            font: Tokens.font.label.large
                            text: qsTr("Some shortcut descriptions are unavailable: Hyprland was loaded without 0xIde's binding annotations. Run ./install --only overrides, then reload Hyprland, to restore them.")
                        }
                    }

                    // Loading, a failure, nothing bound, or nothing matching.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.padding.large
                        Layout.bottomMargin: Tokens.padding.large
                        visible: Keybinds.loading || !!Keybinds.error || Keybinds.matches === 0
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: Keybinds.error ? "error" : Keybinds.loading ? "hourglass_empty" : Keybinds.query ? "search_off" : "keyboard_off"
                            color: Keybinds.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.large
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: Colours.palette.m3onSurfaceVariant
                            text: {
                                if (Keybinds.error)
                                    return qsTr("Could not read the keybinds: %1").arg(Keybinds.error);
                                if (Keybinds.loading)
                                    return qsTr("Reading the keybinds…");
                                if (Keybinds.query)
                                    return qsTr("No shortcut matches “%1”").arg(Keybinds.query);
                                return qsTr("Hyprland has no keybinds registered");
                            }
                        }
                    }

                    StyledListView {
                        id: list

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !Keybinds.loading && !Keybinds.error && Keybinds.matches > 0
                        clip: true
                        spacing: Tokens.spacing.extraSmall
                        model: Keybinds.rows
                        boundsBehavior: Flickable.StopAtBounds

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: list
                        }

                        delegate: Loader {
                            id: row

                            required property var modelData
                            required property int index

                            width: list.width - Tokens.padding.medium
                            sourceComponent: modelData.header !== undefined ? header : bind

                            Component {
                                id: header

                                StyledText {
                                    topPadding: row.index > 0 ? Tokens.padding.medium : 0
                                    bottomPadding: Tokens.padding.extraSmall
                                    text: row.modelData.header
                                    color: Colours.palette.m3primary
                                    font: Tokens.font.label.medium
                                }
                            }

                            Component {
                                id: bind

                                RowLayout {
                                    spacing: Tokens.spacing.medium

                                    // The combination, key by key, in a column
                                    // wide enough that descriptions line up.
                                    Flow {
                                        Layout.preferredWidth: Math.min(card.width * 0.38, 300)
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: Tokens.spacing.extraSmall

                                        Repeater {
                                            model: row.modelData.keys

                                            Keycap {}
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: row.modelData.description + (row.modelData.count > 1 ? ` ×${row.modelData.count}` : "")
                                            color: row.modelData.source === "generic" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                                            font: Tokens.font.body.medium
                                            elide: Text.ElideRight
                                        }

                                        // How it was bound: the action behind a
                                        // generic row, and flags that change
                                        // when or where a bind works.
                                        StyledText {
                                            Layout.fillWidth: true
                                            readonly property var parts: [row.modelData.source === "generic" ? row.modelData.detail : "", row.modelData.submap ? qsTr("submap %1").arg(row.modelData.submap) : "", ...row.modelData.flags].filter(p => p)

                                            visible: parts.length > 0
                                            text: parts.join(" · ")
                                            color: Colours.palette.m3outline
                                            font: Tokens.font.label.small
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component Keycap: StyledRect {
        required property string modelData

        implicitWidth: Math.max(implicitHeight, cap.implicitWidth + Tokens.padding.medium * 2)
        implicitHeight: cap.implicitHeight + Tokens.padding.extraSmall * 2
        radius: Tokens.rounding.small
        color: Colours.palette.m3surfaceContainerHighest
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        StyledText {
            id: cap

            anchors.centerIn: parent
            text: parent.modelData
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.medium
        }
    }
}
