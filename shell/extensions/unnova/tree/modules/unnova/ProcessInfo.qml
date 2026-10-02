pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import "unnova.js" as U

// The selected process. Nothing here follows the list: it shows exactly the
// process that was clicked, by PID and start time, until another is clicked.
// When that process exits it says so, and never moves on to another PID.
StyledRect {
    id: root

    readonly property var info: Processes.selected
    readonly property bool hasSelection: Processes.selectedKey !== ""
    readonly property bool alive: Processes.selectedAlive
    readonly property string context: U.context(info, Quickshell.processId)
    readonly property string ownership: U.ownership(info, Processes.ownUid)

    // "details", "confirm" (an action awaiting a yes), "signals" (choosing one
    // from the full list) or "stuck" (asked to end, still running).
    property string mode: "details"
    property var pending: null
    property string pendingKey
    property string pendingName
    property string resultText
    property bool resultIsError

    function choose(action: var): void {
        stuckCheck.stop();
        pendingKey = "";
        pending = action;
        mode = "confirm";
    }

    function send(action: var, key: string, name: string): void {
        const r = Processes.sendSignal(key, action.signal);
        mode = "details";
        pending = null;
        if (r.result === "sent") {
            resultIsError = false;
            resultText = qsTr("Sent SIG%1 to %2.").arg(action.signal).arg(name);
            // Ending is a request. If it is still running a little later, say
            // so and offer more, but never escalate without being asked.
            if (action.signal === "TERM") {
                pendingKey = key;
                pendingName = name;
                stuckCheck.restart();
            }
        } else {
            resultIsError = true;
            resultText = r.message;
        }
    }

    Connections {
        target: Processes

        function onSelectedKeyChanged(): void {
            stuckCheck.stop();
            root.pendingKey = "";
            root.mode = "details";
            root.pending = null;
            root.resultText = "";
        }

        // A process that was asked to end and did so while the question was up.
        function onSampled(): void {
            if (root.mode === "stuck" && !Processes.isAlive(root.pendingKey)) {
                root.mode = "details";
                root.resultIsError = false;
                root.resultText = qsTr("%1 has exited.").arg(root.pendingName);
                root.pendingKey = "";
            }
        }
    }

    Timer {
        id: stuckCheck

        interval: 4000
        onTriggered: {
            if (Processes.isAlive(root.pendingKey))
                root.mode = "stuck";
            else
                root.pendingKey = "";
        }
    }

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large
    clip: true

    // Nothing selected.
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Tokens.padding.extraLarge * 2
        visible: !root.hasSelection
        spacing: Tokens.spacing.small

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: "touch_app"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Select a process to see what it is and what it is using.")
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        visible: root.hasSelection
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: column

            width: flick.width
            spacing: Tokens.spacing.medium

            // Header
            StyledText {
                Layout.fillWidth: true
                text: root.info.name ?? ""
                font: Tokens.font.title.large
                elide: Text.ElideRight
            }

            StyledRect {
                visible: root.hasSelection && !root.alive
                Layout.fillWidth: true
                implicitHeight: exitedText.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.medium
                color: Colours.palette.m3errorContainer

                StyledText {
                    id: exitedText

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    anchors.leftMargin: Tokens.padding.medium
                    text: qsTr("This process has exited. Its PID may already belong to another process; nothing here acts on it.")
                    wrapMode: Text.WordWrap
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onErrorContainer
                }
            }

            Section {
                text: qsTr("Identity")
            }
            Field {
                label: qsTr("PID")
                value: root.info.pid ?? ""
            }
            Field {
                label: qsTr("User")
                value: root.info.user !== undefined ? `${root.info.user} (${root.info.uid})` : ""
            }

            Section {
                text: qsTr("Resources")
            }
            GraphField {
                label: qsTr("CPU")
                value: U.formatPercent(root.info.cpu)
                buffer: Processes.cpuHistory
                floor: 5
                accent: Colours.palette.m3primary
            }
            GraphField {
                label: qsTr("Memory")
                value: U.formatBytes(root.info.memory)
                buffer: Processes.memoryHistory
                floor: 16 * 1048576
                accent: Colours.palette.m3tertiary
            }
            Field {
                label: qsTr("Resident")
                value: root.info.resident !== undefined ? U.formatBytes(root.info.resident) : ""
                hint: qsTr("including memory shared with other processes")
            }
            Field {
                label: qsTr("Threads")
                value: root.info.threads ?? ""
            }
            Field {
                label: qsTr("Running for")
                value: root.info.uptime !== undefined ? U.formatDuration(root.info.uptime) : ""
                hint: root.info.startedAt ? qsTr("since %1").arg(Qt.formatDateTime(root.info.startedAt, "ddd d MMM, hh:mm:ss")) : ""
            }

            Section {
                text: qsTr("Process")
            }
            Field {
                label: qsTr("State")
                value: U.stateText(root.info.state)
            }
            Field {
                label: qsTr("Parent")
                value: root.info.ppid ? `${root.info.parentName ?? "?"} · ${root.info.ppid}` : qsTr("None")
                link: !!root.info.parentKey
                onActivated: Processes.selectedKey = root.info.parentKey
            }
            Field {
                label: qsTr("Executable")
                value: root.info.exeReadable ? root.info.exe : qsTr("Not readable")
                copyable: !!root.info.exeReadable
                lines: 2
            }
            Field {
                label: qsTr("Command")
                value: root.info.command || (root.info.kernelThread ? qsTr("None (kernel thread)") : root.info.commandReadable === false ? qsTr("Not readable") : qsTr("None"))
                copyable: !!root.info.command
                lines: 4
            }

            Note {
                visible: root.context !== ""
                icon: "info"
                text: root.context
            }

            Note {
                visible: root.ownership !== ""
                icon: "lock"
                text: root.ownership
            }

            Note {
                visible: root.resultText !== ""
                icon: root.resultIsError ? "error" : "check_circle"
                text: root.resultText
                error: root.resultIsError
            }

            Section {
                text: qsTr("Actions")
            }

            // The usual case: end, or more.
            RowLayout {
                visible: root.mode === "details"
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "close"
                    text: qsTr("End task")
                    disabled: !root.alive
                    isRound: true
                    verticalPadding: Tokens.padding.medium
                    onClicked: root.choose(U.action("end"))
                }

                IconTextButton {
                    id: moreButton

                    icon: "more_horiz"
                    text: qsTr("Actions…")
                    type: IconTextButton.Tonal
                    disabled: !root.alive
                    isRound: true
                    verticalPadding: Tokens.padding.medium
                    onClicked: actionsMenu.expanded = !actionsMenu.expanded
                }
            }

            // An action, explained, waiting for a yes.
            ColumnLayout {
                visible: root.mode === "confirm" && root.pending !== null
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.pending ? qsTr("%1 · SIG%2").arg(root.pending.title).arg(root.pending.signal) : ""
                    font: Tokens.font.title.small
                    color: root.pending?.destructive ? Colours.palette.m3error : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.pending?.explanation ?? ""
                    wrapMode: Text.WordWrap
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        Layout.fillWidth: true
                        text: qsTr("Cancel")
                        type: TextButton.Tonal
                        isRound: true
                        verticalPadding: Tokens.padding.medium
                        onClicked: {
                            root.mode = "details";
                            root.pending = null;
                        }
                    }

                    TextButton {
                        Layout.fillWidth: true
                        text: root.pending?.title ?? ""
                        isRound: true
                        verticalPadding: Tokens.padding.medium
                        disabled: !root.alive
                        inactiveColour: root.pending?.destructive ? Colours.palette.m3error : Colours.palette.m3primary
                        inactiveOnColour: root.pending?.destructive ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                        onClicked: root.send(root.pending, Processes.selectedKey, root.info.name ?? "")
                    }
                }
            }

            // Every signal UnNova sends, for when the named actions are not it.
            ColumnLayout {
                visible: root.mode === "signals"
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Choose a signal")
                    font: Tokens.font.title.small
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: Processes.signalNames()

                        TextButton {
                            required property string modelData

                            text: modelData
                            type: TextButton.Tonal
                            isRound: true
                            onClicked: root.choose(U.signalAction(modelData))
                        }
                    }
                }

                TextButton {
                    Layout.fillWidth: true
                    text: qsTr("Cancel")
                    type: TextButton.Text
                    onClicked: root.mode = "details"
                }
            }

            // Asked to end, and still here. Waiting or forcing is the user's call.
            ColumnLayout {
                visible: root.mode === "stuck"
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%1 did not exit.").arg(root.pendingName)
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("It may still be finishing up, or asking something in one of its windows. Force stop ends it immediately: it cannot clean up or save, and unsaved work may be lost.")
                    wrapMode: Text.WordWrap
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        Layout.fillWidth: true
                        text: qsTr("Keep waiting")
                        type: TextButton.Tonal
                        isRound: true
                        verticalPadding: Tokens.padding.medium
                        onClicked: {
                            root.mode = "details";
                            stuckCheck.restart();
                        }
                    }

                    TextButton {
                        Layout.fillWidth: true
                        text: qsTr("Force stop")
                        isRound: true
                        verticalPadding: Tokens.padding.medium
                        inactiveColour: Colours.palette.m3error
                        inactiveOnColour: Colours.palette.m3onError
                        onClicked: {
                            const key = root.pendingKey;
                            root.pendingKey = "";
                            root.send(U.action("force"), key, root.pendingName);
                        }
                    }
                }
            }
        }
    }

    Menu {
        id: actionsMenu

        parent: root.QsWindow.window?.contentItem ?? null
        attachTo: moreButton
        thisSideY: Menu.Bottom
        attachSideY: Menu.Top
        marginY: -Tokens.spacing.small
        active: null
        onItemSelected: active = null

        items: [
            ActionItem {
                action: U.action("force")
            },
            ActionItem {
                action: U.action("pause")
            },
            ActionItem {
                action: U.action("resume")
            },
            ActionItem {
                action: U.action("hangup")
            },
            ActionItem {
                action: U.action("interrupt")
            },
            MenuItem {
                text: qsTr("Send signal…")
                icon: "send"
                onClicked: root.mode = "signals"
            }
        ]
    }

    component ActionItem: MenuItem {
        required property var action

        text: action.title
        icon: action.icon
        onClicked: root.choose(action)
    }

    component Section: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        Layout.bottomMargin: Tokens.spacing.extraSmall
        font: Tokens.font.label.builders.large.weight(Font.DemiBold).build()
        color: Colours.palette.m3primary
        text: ""
    }

    component Field: ColumnLayout {
        id: field

        required property string label
        property var value
        property string hint
        property bool copyable
        property bool link
        property int lines: 1
        property bool copied

        signal activated

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            text: field.label
            font: Tokens.font.label.medium
            color: Colours.palette.m3onSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                id: valueText

                Layout.fillWidth: true
                text: String(field.value ?? "")
                font: field.lines > 1 ? Tokens.font.mono.small : Tokens.font.body.medium
                color: field.link ? Colours.palette.m3primary : Colours.palette.m3onSurface
                wrapMode: field.lines > 1 ? Text.Wrap : Text.NoWrap
                lineHeight: field.lines > 1 ? 1.2 : 1
                maximumLineCount: field.lines
                elide: Text.ElideRight

                MouseArea {
                    anchors.fill: parent
                    enabled: field.link
                    cursorShape: field.link ? Qt.PointingHandCursor : undefined
                    onClicked: field.activated()
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                visible: field.copyable
                icon: field.copied ? "check" : "content_copy"
                type: IconButton.Text
                onClicked: {
                    Quickshell.clipboardText = String(field.value);
                    field.copied = true;
                    copiedReset.restart();
                }

                Timer {
                    id: copiedReset

                    interval: 1500
                    onTriggered: field.copied = false
                }
            }
        }

        StyledText {
            visible: field.hint !== ""
            Layout.fillWidth: true
            text: field.hint
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
            lineHeight: 1.15
        }
    }

    component GraphField: ColumnLayout {
        id: graph

        required property string label
        required property string value
        required property CircularBuffer buffer
        required property real floor
        required property color accent

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: graph.label
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                text: graph.value
                font: Tokens.font.body.medium
                color: graph.accent
            }
        }

        SparklineItem {
            id: spark

            Layout.fillWidth: true
            implicitHeight: 36
            line1: graph.buffer
            line1Color: graph.accent
            line1FillAlpha: 0.18
            maxValue: Math.max(graph.buffer.maximum * 1.2, graph.floor)
            historyLength: Processes.historyLength

            Connections {
                target: graph.buffer

                function onValuesChanged(): void {
                    slide.restart();
                }
            }

            NumberAnimation {
                id: slide

                target: spark
                property: "slideProgress"
                from: 0
                to: 1
                duration: 1000
            }
        }
    }

    component Note: StyledRect {
        id: note

        property string icon
        property string text
        property bool error

        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        implicitHeight: noteRow.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.medium
        color: error ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainerHigh

        RowLayout {
            id: noteRow

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignTop
                text: note.icon
                color: note.error ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: note.text
                wrapMode: Text.WordWrap
                font: Tokens.font.body.small
                color: note.error ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
            }
        }
    }
}
