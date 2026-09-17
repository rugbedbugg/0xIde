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
    readonly property bool busy: request.running || waiting
    readonly property int actionIndex: action.menuItems.indexOf(action.active)
    readonly property string destination: {
        if (GlobalConfig.ai.backend === "managed")
            return qsTr("Local model on this computer");
        if (GlobalConfig.ai.backend === "external")
            return GlobalConfig.ai.backendUrl;
        return qsTr("No AI backend configured");
    }

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
        pendingQuery = instructions[actionIndex] + "\n\n" + snapshot;
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
    implicitWidth: Math.min(parent.width - Tokens.padding.extraLarge * 2, 960)
    implicitHeight: Math.min(parent.height - Tokens.padding.extraLarge * 2, 700)
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            // Header: what this is, where the AI would send it, and a way out.
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: "document_scanner"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.large
                    fill: 1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Text extraction")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.maximumWidth: root.width / 2
                            text: root.destination
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideMiddle
                        }
                        TextButton {
                            visible: !GlobalConfig.ai.backend
                            type: TextButton.Text
                            font: Tokens.font.label.small
                            text: qsTr("Set one up")
                            onClicked: root.activeTab = 2
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    type: IconButton.Text
                    icon: "close"
                    onClicked: root.dismissed()
                }
            }

            // Navigation. Nothing else in the card is a filled pill, so these
            // read as tabs rather than as one more row of buttons.
            RowLayout {
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: [qsTr("Text"), qsTr("AI response"), qsTr("Settings")]

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
            }

            // One banner shape for every message this card needs to show.
            StyledRect {
                Layout.fillWidth: true
                visible: !!root.notice || root.offerInstall
                radius: Tokens.rounding.medium
                color: Colours.palette.m3tertiaryContainer
                implicitHeight: banner.implicitHeight + Tokens.padding.medium * 2

                ColumnLayout {
                    id: banner

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignTop
                            text: root.offerInstall ? "download" : "info"
                            color: Colours.palette.m3onTertiaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Colours.palette.m3onTertiaryContainer
                            text: root.offerInstall ? qsTr("AI needs a backend. Would you like to install a local model?") : root.notice
                        }
                    }
                    RowLayout {
                        visible: root.offerInstall
                        spacing: Tokens.spacing.small

                        TextButton {
                            type: TextButton.Text
                            text: qsTr("Install it for me")
                            onClicked: {
                                root.offerInstall = false;
                                root.activeTab = 2;
                                settings.confirmInstall = true;
                                AiRuntime.refresh();
                            }
                        }
                        TextButton {
                            type: TextButton.Text
                            text: qsTr("I'll do it myself")
                            onClicked: {
                                root.offerInstall = false;
                                root.activeTab = 2;
                            }
                        }
                        TextButton {
                            type: TextButton.Text
                            text: qsTr("Not now")
                            onClicked: {
                                root.offerInstall = false;
                                root.pendingQuery = "";
                            }
                        }
                    }
                }
            }

            // The content sits on its own surface, so the text has an edge.
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerHigh

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    // Editing controls, kept light so they do not compete with
                    // the tabs above or the actions below.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.activeTab === 0
                        spacing: Tokens.spacing.extraSmall

                        TextButton {
                            visible: !!root.structured.words
                            type: TextButton.Text
                            font: Tokens.font.label.large
                            text: root.tableMode ? qsTr("Show as text") : qsTr("Show as table")
                            onClicked: {
                                root.tableMode = !root.tableMode;
                                GlobalConfig.ai.tableMode = root.tableMode;
                            }
                        }
                        TextButton {
                            type: TextButton.Text
                            font: Tokens.font.label.large
                            text: qsTr("Restore original")
                            onClicked: root.reset()
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        IconButton {
                            visible: !root.tableMode
                            type: IconButton.Text
                            icon: "undo"
                            disabled: !extractedText.canUndo
                            onClicked: extractedText.undo()
                        }
                        IconButton {
                            visible: !root.tableMode
                            type: IconButton.Text
                            icon: "redo"
                            disabled: !extractedText.canRedo
                            onClicked: extractedText.redo()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.activeTab === 0 && root.tableMode
                        spacing: Tokens.spacing.small

                        StyledTextField {
                            id: boundaries

                            objectName: "tableBoundaries"
                            Layout.fillWidth: true

                            placeholderText: qsTr("Column boundaries in pixels, e.g. 150, 420, 650")
                        }
                        TextButton {
                            type: TextButton.Tonal
                            text: qsTr("Rebuild")
                            onClicked: root.rebuildTable()
                        }
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: root.activeTab

                        Item {
                            ScrollView {
                                anchors.fill: parent
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
                                    padding: 0
                                    background: null
                                }
                            }
                            ScrollView {
                                anchors.fill: parent
                                visible: root.tableMode
                                clip: true

                                Column {
                                    spacing: Tokens.spacing.extraSmall

                                    Repeater {
                                        model: root.rows

                                        Row {
                                            id: tableRow

                                            required property int index
                                            required property var modelData

                                            spacing: Tokens.spacing.extraSmall

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
                                                    font: Tokens.font.mono.small
                                                    leftPadding: Tokens.padding.small
                                                    rightPadding: Tokens.padding.small
                                                    background: StyledRect {
                                                        radius: Tokens.rounding.small
                                                        color: Colours.palette.m3surfaceContainerHighest
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
                            spacing: Tokens.spacing.small

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: request.error ? "error" : request.status === "complete" ? "check_circle" : "auto_awesome"
                                    color: request.error ? Colours.palette.m3error : Colours.palette.m3outline
                                    fontStyle: Tokens.font.icon.small
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    color: request.error ? Colours.palette.m3error : Colours.palette.m3outline
                                    font: Tokens.font.label.large
                                    text: root.waiting ? qsTr("Starting the local model...") : request.error || (request.status === "stopped" ? qsTr("Stopped. Partial response kept.") : request.status === "loading" ? qsTr("Generating...") : request.status === "complete" ? qsTr("Complete") : qsTr("Pick an action below, then Ask AI."))
                                }
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
                                    padding: 0
                                    background: null
                                }
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
                }
            }

            // One filled button, so it is obvious which control submits.
            RowLayout {
                Layout.fillWidth: true
                visible: root.activeTab !== 2
                spacing: Tokens.spacing.small

                SplitButton {
                    id: action

                    Layout.alignment: Qt.AlignVCenter
                    type: SplitButton.Tonal
                    menuOnTop: true
                    // Menu resolves its own parent from QsWindow, which is not
                    // there yet while this card is incubating, and the window is
                    // masked to the card anyway. Parent it here and open it
                    // rightwards so all of it stays inside the mask.
                    menu.parent: root
                    menu.attachSideX: Menu.Left
                    menu.thisSideX: Menu.Left
                    stateLayer.onClicked: action.expanded = !action.expanded

                    menuItems: [
                        MenuItem {
                            text: qsTr("Explain")
                            icon: "lightbulb"
                        },
                        MenuItem {
                            text: qsTr("Summarize")
                            icon: "summarize"
                        },
                        MenuItem {
                            text: qsTr("Translate")
                            icon: "translate"
                        },
                        MenuItem {
                            text: qsTr("Custom")
                            icon: "edit"
                        }
                    ]
                }
                StyledTextField {
                    id: target

                    visible: root.actionIndex === 2
                    Layout.fillWidth: true
                    placeholderText: qsTr("Target language")
                    text: GlobalConfig.ai.translateLanguage
                    onEditingFinished: GlobalConfig.ai.translateLanguage = text
                }
                StyledTextField {
                    id: custom

                    visible: root.actionIndex === 3
                    Layout.fillWidth: true
                    placeholderText: qsTr("What should the model do with this text?")
                }
                Item {
                    Layout.fillWidth: true
                    visible: root.actionIndex < 2
                }
                IconTextButton {
                    type: IconTextButton.Tonal
                    icon: "content_copy"
                    text: qsTr("Copy")
                    disabled: !root.activeQuery.trim()
                    onClicked: Quickshell.execDetached(["wl-copy", "-n", "--", root.activeQuery])
                }
                IconTextButton {
                    type: IconTextButton.Tonal
                    icon: "travel_explore"
                    text: qsTr("Search")
                    disabled: !root.activeQuery.trim()
                    onClicked: Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(root.activeQuery)])
                }
                IconTextButton {
                    type: IconTextButton.Filled
                    icon: root.busy ? "stop" : "auto_awesome"
                    text: root.busy ? qsTr("Stop") : qsTr("Ask AI")
                    disabled: !root.busy && (!root.activeQuery.trim() || (root.actionIndex === 3 && !custom.text.trim()))
                    onClicked: {
                        if (root.busy)
                            root.cancel();
                        else
                            root.submit();
                    }
                }
            }
        }
    }
}
