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
    property bool showSettings: false
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
    // A selection anywhere wins; otherwise the whole extracted text.
    readonly property string activeQuery: {
        if (aiText.selectedText)
            return aiText.selectedText;
        if (tableMode)
            return activeCell?.selectedText || tableText;
        return extractedText.selectedText || extractedText.text;
    }
    readonly property bool busy: request.running || waiting
    readonly property bool hasResponse: busy || !!request.text || !!request.error
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
        showSettings = false;
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
                showSettings = true;
                notice = qsTr("A local model is installed. Choose a backend in Settings, then submit again.");
                return;
            }
            offerInstall = true;
            return;
        }
        if (GlobalConfig.ai.backend === "managed") {
            if (!AiRuntime.info.installed) {
                showSettings = true;
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
    implicitWidth: Math.min(parent.width - Tokens.padding.extraLarge * 2, 900)
    implicitHeight: Math.min(parent.height - Tokens.padding.extraLarge * 2, 660)
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
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.busy)
                root.cancel();
            else if (root.showSettings)
                root.showSettings = false;
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

            // Header: what this is, where the AI would send it, and the only
            // two things that are not about the text itself.
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
                        text: root.showSettings ? qsTr("OCR and AI settings") : qsTr("Text extraction")
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
                            visible: !GlobalConfig.ai.backend && !root.showSettings
                            type: TextButton.Text
                            font: Tokens.font.label.small
                            text: qsTr("Set one up")
                            onClicked: root.showSettings = true
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    type: IconButton.Text
                    isToggle: true
                    checked: root.showSettings
                    icon: "settings"
                    onClicked: root.showSettings = !root.showSettings
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    type: IconButton.Text
                    icon: "close"
                    onClicked: root.dismissed()
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
                            text: qsTr("Install")
                            onClicked: {
                                root.offerInstall = false;
                                root.showSettings = true;
                                settings.confirmInstall = true;
                                AiRuntime.refresh();
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

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: root.showSettings
                    clip: true
                    contentWidth: availableWidth

                    AiSettings {
                        id: settings

                        width: parent.width
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: !root.showSettings
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Extracted text")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.large
                        }
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
                        visible: root.tableMode
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
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 100

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

                    // The response grows under the text rather than beside it in
                    // a tab, and takes no room at all until there is one.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        visible: root.hasResponse
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
                            text: root.waiting ? qsTr("Starting the local model...") : request.error || (request.status === "stopped" ? qsTr("Stopped. Partial response kept.") : request.status === "loading" ? qsTr("Generating...") : qsTr("AI response"))
                        }
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 140
                        visible: root.hasResponse
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
            }

            // One filled button, so it is obvious which control submits.
            RowLayout {
                Layout.fillWidth: true
                visible: !root.showSettings
                spacing: Tokens.spacing.small

                SplitButton {
                    id: action

                    Layout.alignment: Qt.AlignVCenter
                    type: SplitButton.Tonal
                    menuOnTop: true
                    // Menu resolves its own parent through QsWindow, which is
                    // not attached while this card is incubating, and the window
                    // is masked to the card anyway. Parent it here and open it
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
