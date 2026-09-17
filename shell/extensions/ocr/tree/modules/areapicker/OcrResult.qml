pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    required property string text
    property var structured: ({})
    property int activeTab: 0
    property bool tableMode: GlobalConfig.ai.tableMode && !!structured.words
    property var rows: []
    property int tableRevision: 0
    property var activeCell: null
    property string pendingQuery: ""
    property string notice: ""
    property bool offerInstall: false
    property bool waiting: false
    readonly property string tableText: {
        tableRevision;
        return rows.map(row => row.join("\t")).join("\n");
    }
    readonly property string activeQuery: activeTab === 1 ? (aiText.selectedText || request.text) : tableMode ? (activeCell?.selectedText || tableText) : (extractedText.selectedText || extractedText.text)
    readonly property string responseStatus: request.status
    readonly property bool busy: request.running || waiting

    signal dismissed

    function reset(): void {
        cancel();
        tableMode = GlobalConfig.ai.tableMode && !!structured.words;
        extractedText.text = text;
        rows = structured.rows ? structured.rows.map(row => row.slice()) : [];
        activeCell = null;
        boundaries.text = (structured.boundaries ?? []).map(x => Math.round(x)).join(", ");
        notice = "";
        offerInstall = false;
        activeTab = 0;
    }
    function cancel(): void {
        waiting = false;
        pendingQuery = "";
        request.cancel();
        AiRuntime.release();
    }
    function submit(): void {
        if (busy || !activeQuery.trim())
            return;
        const snapshot = activeQuery;
        const instructions = ["Explain the following text clearly.", "Summarize the following text.", "Translate the following text into " + target.text + ".", custom.text];
        pendingQuery = instructions[action.currentIndex] + "\n\n" + snapshot;
        notice = "";
        if (!GlobalConfig.ai.backend) {
            if (AiRuntime.info.installed) {
                activeTab = 2;
                notice = qsTr("A local model is installed. Choose a backend in Settings, then submit again.");
                return;
            }
            offerInstall = true;
            return;
        }
        activeTab = 1;
        if (GlobalConfig.ai.backend === "managed") {
            if (!AiRuntime.info.installed) {
                activeTab = 2;
                notice = qsTr("Install the local model below first.");
                return;
            }
            // A conservative UTF-8 byte ceiling also bounds byte-tokenized input.
            const bytes = unescape(encodeURIComponent(pendingQuery + GlobalConfig.ai.systemPrompt)).length;
            if (bytes > 3072) {
                notice = qsTr("Text is too long for this local model. Select a shorter passage (up to 3072 UTF-8 bytes including instructions). Nothing was sent.");
                pendingQuery = "";
                return;
            }
            waiting = true;
            AiRuntime.start();
        } else
            send(GlobalConfig.ai.backendUrl);
    }
    function send(endpoint: string): void {
        waiting = false;
        const payload = {
            messages: [],
            stream: true,
            max_tokens: 512
        };
        if (GlobalConfig.ai.systemPrompt)
            payload.messages.push({
                role: "system",
                content: GlobalConfig.ai.systemPrompt
            });
        payload.messages.push({
            role: "user",
            content: pendingQuery
        });
        if (GlobalConfig.ai.backend === "external" && GlobalConfig.ai.model)
            payload.model = GlobalConfig.ai.model;
        pendingQuery = "";
        request.send(endpoint, JSON.stringify(payload));
    }
    function rebuildTable(): void {
        const cuts = boundaries.text.trim() ? boundaries.text.split(",").map(x => Number(x.trim())) : [];
        if (cuts.some((x, i) => !isFinite(x) || x < 0 || (i > 0 && x <= cuts[i - 1]))) {
            notice = qsTr("Enter increasing column boundaries in image pixels, separated by commas.");
            return;
        }
        const lines = structured.lines ?? [];
        rows = lines.map(words => {
            const cells = Array(cuts.length + 1).fill("");
            words.forEach(word => {
                const column = cuts.filter(cut => word.left >= cut).length;
                cells[column] += (cells[column] ? " " : "") + word.text;
            });
            return cells;
        });
        activeCell = null;
        notice = qsTr("Table rebuilt from the original OCR positions.");
    }

    anchors.centerIn: parent
    implicitWidth: Math.min(parent.width - 40, 1100)
    implicitHeight: Math.min(parent.height - 60, 780)
    focus: true

    onTextChanged: Qt.callLater(reset)
    onStructuredChanged: Qt.callLater(reset)
    Component.onCompleted: reset()
    Component.onDestruction: cancel()

    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.WindowShortcut
        onActivated: root.submit()
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        context: Qt.WindowShortcut
        onActivated: root.activeTab = (root.activeTab + 1) % 3
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.busy)
                root.cancel();
            else
                root.dismissed();
        }
    }

    AiRequest {
        id: request

        onFinished: AiRuntime.release()
    }
    Connections {
        function onReady(): void {
            if (root.waiting)
                root.send(AiRuntime.endpoint);
        }
        function onErrorChanged(): void {
            if (root.waiting && AiRuntime.error) {
                root.waiting = false;
                root.notice = AiRuntime.error;
            }
        }

        target: AiRuntime
    }
    Elevation {
        anchors.fill: parent
        radius: Tokens.rounding.large
        level: 3
    }
    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Qt.alpha(Colours.palette.m3surfaceContainer, 1)
        border.color: Colours.palette.m3outlineVariant
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacing.large
            spacing: Tokens.spacing.small

            RowLayout {
                Repeater {
                    model: [qsTr("Extracted text"), qsTr("AI response"), qsTr("Settings")]

                    TextButton {
                        required property int index
                        required property string modelData

                        text: modelData
                        isToggle: true
                        checked: root.activeTab === index
                        onClicked: root.activeTab = index
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                TextButton {
                    text: qsTr("Close")
                    onClicked: root.dismissed()
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: !!root.notice
                wrapMode: Text.Wrap
                text: root.notice
            }
            ColumnLayout {
                visible: root.offerInstall

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("AI needs a backend. Would you like to install a local model?")
                }
                RowLayout {
                    TextButton {
                        text: qsTr("Yes, install it for me")
                        onClicked: {
                            root.offerInstall = false;
                            root.activeTab = 2;
                            settings.confirmInstall = true;
                            AiRuntime.refresh();
                        }
                    }
                    TextButton {
                        text: qsTr("I'll install it myself")
                        onClicked: {
                            root.offerInstall = false;
                            root.activeTab = 2;
                        }
                    }
                    TextButton {
                        text: qsTr("Not now")
                        onClicked: {
                            root.offerInstall = false;
                            root.pendingQuery = "";
                        }
                    }
                }
            }
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.activeTab

                ColumnLayout {
                    RowLayout {
                        TextButton {
                            visible: !!root.structured.words
                            text: root.tableMode ? qsTr("Switch to text") : qsTr("Switch to table")
                            onClicked: {
                                root.tableMode = !root.tableMode;
                                GlobalConfig.ai.tableMode = root.tableMode;
                            }
                        }
                        TextButton {
                            text: qsTr("Restore original")
                            onClicked: root.reset()
                        }
                        TextButton {
                            visible: !root.tableMode
                            text: qsTr("Undo")
                            enabled: extractedText.canUndo
                            onClicked: extractedText.undo()
                        }
                        TextButton {
                            visible: !root.tableMode
                            text: qsTr("Redo")
                            enabled: extractedText.canRedo
                            onClicked: extractedText.redo()
                        }
                    }
                    RowLayout {
                        visible: root.tableMode

                        StyledTextField {
                            id: boundaries

                            objectName: "tableBoundaries"
                            Layout.fillWidth: true

                            placeholderText: qsTr("Column boundaries in pixels, e.g. 150, 420, 650")
                        }
                        TextButton {
                            text: qsTr("Rebuild (resets cell edits)")
                            onClicked: root.rebuildTable()
                        }
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.tableMode
                        clip: true

                        TextArea {
                            id: extractedText

                            objectName: "ocrEditor"

                            selectByMouse: true
                            persistentSelection: true
                            Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
                            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
                            wrapMode: TextArea.Wrap
                            font: Tokens.font.mono.medium
                            color: Colours.palette.m3onSurface
                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.tableMode
                        clip: true

                        Column {
                            Repeater {
                                model: root.rows

                                Row {
                                    id: tableRow

                                    required property int index
                                    required property var modelData

                                    Repeater {
                                        model: tableRow.modelData

                                        TextField {
                                            required property int index
                                            required property string modelData

                                            objectName: "ocrCell_" + tableRow.index + "_" + index
                                            width: 200
                                            text: modelData
                                            selectByMouse: true
                                            persistentSelection: true
                                            color: Colours.palette.m3onSurface
                                            background: Rectangle {
                                                color: Colours.palette.m3surfaceContainerHigh
                                                border.width: 1
                                                border.color: Colours.palette.m3outlineVariant
                                            }
                                            onActiveFocusChanged: if (activeFocus)
                                                root.activeCell = this
                                            onTextEdited: {
                                                root.rows[tableRow.index][index] = text;
                                                root.tableRevision++;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.waiting ? qsTr("Starting local model...") : request.error || (request.status === "stopped" ? qsTr("Stopped. Partial response retained.") : request.status === "loading" ? qsTr("Generating...") : request.status === "complete" ? qsTr("Complete") : qsTr("Choose an action below."))
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            id: aiText

                            objectName: "aiResponse"

                            readOnly: true
                            selectByMouse: true
                            persistentSelection: true
                            Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
                            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
                            text: request.text
                            wrapMode: TextArea.Wrap
                            font: Tokens.font.mono.medium
                            color: Colours.palette.m3onSurface
                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                    }
                    TextButton {
                        visible: root.busy
                        text: qsTr("Stop")
                        onClicked: root.cancel()
                    }
                }
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    AiSettings {
                        id: settings

                        width: parent.width
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.activeTab !== 2
                wrapMode: Text.Wrap
                text: GlobalConfig.ai.backend === "managed" ? qsTr("AI destination: local BitNet on this computer") : GlobalConfig.ai.backend === "external" ? qsTr("AI destination: %1").arg(GlobalConfig.ai.backendUrl) : qsTr("AI backend not configured")
            }
            RowLayout {
                visible: root.activeTab !== 2

                ComboBox {
                    id: action

                    objectName: "aiAction"

                    model: [qsTr("Explain"), qsTr("Summarize"), qsTr("Translate"), qsTr("Custom")]
                    Layout.preferredWidth: 160
                }
                StyledTextField {
                    id: target

                    visible: action.currentIndex === 2
                    Layout.fillWidth: true
                    placeholderText: qsTr("Target language")
                    text: GlobalConfig.ai.translateLanguage
                    onEditingFinished: GlobalConfig.ai.translateLanguage = text
                }
                StyledTextField {
                    id: custom

                    visible: action.currentIndex === 3
                    Layout.fillWidth: true
                    placeholderText: qsTr("What should AI do with this text?")
                }
                Item {
                    Layout.fillWidth: true
                    visible: action.currentIndex < 2
                }
                TextButton {
                    text: qsTr("Copy")
                    onClicked: Quickshell.execDetached(["wl-copy", root.activeQuery])
                }
                TextButton {
                    text: qsTr("Search")
                    enabled: !!root.activeQuery.trim()
                    onClicked: Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(root.activeQuery)])
                }
                TextButton {
                    text: qsTr("Ask AI")
                    enabled: !root.busy && !!root.activeQuery.trim() && (action.currentIndex !== 3 || !!custom.text.trim())
                    onClicked: root.submit()
                }
            }
        }
    }
}
