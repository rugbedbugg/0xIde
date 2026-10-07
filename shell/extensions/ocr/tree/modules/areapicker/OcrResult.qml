pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
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
    // Whatever is selected in the response, which spans several text blocks.
    property string responseSelection: ""
    readonly property string activeQuery: {
        if (responseSelection)
            return responseSelection;
        if (tableMode)
            return activeCell?.selectedText || tableText;
        return extractedText.selectedText || extractedText.text;
    }
    // Translate runs on the offline translator when both languages are
    // installed; everything else, and Translate without them, asks the model.
    property bool localMode: false
    property string localText: ""
    property string localError: ""
    readonly property string responseText: localMode ? localText : request.text
    readonly property string responseError: localMode ? localError : request.error
    readonly property bool offlineTranslate: Translator.canTranslate(GlobalConfig.ai.translateFrom, GlobalConfig.ai.translateLanguage)
    readonly property bool busy: request.running || waiting || Translator.translating
    readonly property bool hasResponse: busy || !!responseText || !!responseError
    // The response split at ``` fences: prose is rendered as Markdown, code is
    // shown as it came, in the terminal's font. An unclosed fence while the
    // answer is still streaming makes the rest code.
    readonly property var segments: {
        const out = [];
        let code = false, buffer = [];
        const flush = () => {
            const text = buffer.join("\n");
            if (text.trim())
                out.push({ code, text: code ? text : text.trim() });
            buffer = [];
        };
        for (const line of responseText.split("\n")) {
            if (/^\s*```/.test(line)) {
                flush();
                code = !code;
            } else {
                buffer.push(line);
            }
        }
        flush();
        return out;
    }
    // foot's own font and size, so code reads as it would in the terminal.
    property string codeFamily: Tokens.font.mono.medium.family
    property real codeSize: Tokens.font.mono.medium.pointSize
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
        responseSelection = "";
    }
    function cancel(): void {
        waiting = false;
        pendingQuery = "";
        request.cancel();
        Translator.cancel();
        AiRuntime.release();
    }
    function submit(): void {
        if (busy || !activeQuery.trim())
            return;
        const snapshot = activeQuery;
        localMode = actionIndex === 2 && offlineTranslate;
        if (localMode) {
            localText = "";
            localError = "";
            notice = "";
            Translator.translate(snapshot, GlobalConfig.ai.translateFrom, GlobalConfig.ai.translateLanguage);
            return;
        }
        const language = Translator.name(GlobalConfig.ai.translateLanguage) || target.text;
        const instructions = ["Explain the following text clearly.", "Summarize the following text.", "Translate the following text into " + language + ".", custom.text, "Write the minimal but complete, working code that solves the following. Reply with one code block in the most suitable language, then at most two sentences on how to run it."];
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
    // Wider once there is a response, so the text and the answer sit side by side.
    implicitWidth: Math.min(parent.width - Tokens.padding.extraLarge * 2, hasResponse ? 1400 : 900)
    // Hug the content rather than always taking a fixed slab, so a short
    // capture and the settings view do not leave half the card empty.
    implicitHeight: Math.min(parent.height - Tokens.padding.extraLarge * 2, Math.max(360, layout.implicitHeight + Tokens.padding.large * 2))
    focus: true

    Behavior on implicitHeight {
        Anim {
            type: Anim.Emphasized
        }
    }
    Behavior on implicitWidth {
        Anim {
            type: Anim.Emphasized
        }
    }

    FileView {
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/foot/foot.ini`
        onLoaded: {
            let main = true;
            for (const raw of text().split("\n")) {
                const line = raw.trim();
                if (line.startsWith("["))
                    main = line === "[main]";
                const match = main && line.match(/^font\s*=\s*([^:,]+)(?::size=([\d.]+))?/);
                if (match) {
                    root.codeFamily = match[1].trim();
                    if (match[2])
                        root.codeSize = Number(match[2]);
                    break;
                }
            }
        }
    }

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
        function onTranslated(text: string): void {
            root.localText = text;
        }
        function onFailed(error: string): void {
            root.localError = error;
        }

        target: Translator
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
            id: layout

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
            // With settings closed, it is also where an installation in
            // progress stays visible.
            StyledRect {
                readonly property bool installing: AiRuntime.installing && !root.showSettings

                Layout.fillWidth: true
                visible: !!root.notice || root.offerInstall || installing
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

                    AiInstallProgress {
                        Layout.fillWidth: true
                        visible: AiRuntime.installing && !root.showSettings
                        textColour: Colours.palette.m3onTertiaryContainer
                        subtleColour: Colours.palette.m3onTertiaryContainer
                        accentColour: Colours.palette.m3onTertiaryContainer
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.notice || root.offerInstall
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

            // Settings sit on one surface; the text and the response each get
            // their own. Once there is a response they sit side by side, the
            // response's title above its own pane rather than inside it.
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Anchored children do not size their parent, so report what
                // whichever view is showing actually needs.
                implicitHeight: root.showSettings ? settings.implicitHeight + Tokens.padding.medium * 2 : content.implicitHeight
                radius: Tokens.rounding.medium
                color: root.showSettings ? Colours.palette.m3surfaceContainerHigh : "transparent"

                ScrollView {
                    id: settingsView

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: root.showSettings
                    clip: true
                    contentWidth: availableWidth

                    AiSettings {
                        id: settings

                        // parent here is the scroll view's own content item,
                        // whose width follows this item's, so binding to it
                        // leaves wrapping text with no width to wrap against.
                        width: settingsView.availableWidth
                    }
                }

                GridLayout {
                    id: content

                    readonly property bool sideBySide: root.hasResponse
                    // Each column gets exactly half. Left to fillWidth alone the
                    // layout hands nearly all of it to the response.
                    readonly property real columnWidth: sideBySide ? (width - columnSpacing) / 2 : width

                    anchors.fill: parent
                    visible: !root.showSettings
                    columns: sideBySide ? 2 : 1
                    rowSpacing: Tokens.spacing.small
                    columnSpacing: Tokens.spacing.medium

                    // Both titles sit above their panes, so the two panes share
                    // a row and are always the same height.
                    RowLayout {
                        Layout.row: 0
                        Layout.column: 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: content.columnWidth - Tokens.padding.medium * 2
                        Layout.maximumWidth: content.columnWidth - Tokens.padding.medium * 2
                        Layout.leftMargin: Tokens.padding.medium
                        Layout.rightMargin: Tokens.padding.medium
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

                    StyledRect {
                        Layout.row: 1
                        Layout.column: 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: content.columnWidth
                        Layout.maximumWidth: content.columnWidth
                        implicitHeight: extractedPane.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHigh

                        ColumnLayout {
                            id: extractedPane

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

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
                                Layout.preferredHeight: 180

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
                        }
                    }

                    // The response takes no room at all until there is one.
                    RowLayout {
                        Layout.row: content.sideBySide ? 0 : 2
                        Layout.column: content.sideBySide ? 1 : 0
                        Layout.fillWidth: true
                        // Margins sit outside the width a layout item is given.
                        Layout.preferredWidth: content.columnWidth - Tokens.padding.medium * 2
                        Layout.maximumWidth: content.columnWidth - Tokens.padding.medium * 2
                        Layout.leftMargin: Tokens.padding.medium
                        Layout.rightMargin: Tokens.padding.medium
                        visible: root.hasResponse
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: root.responseError ? "error" : root.busy ? (root.localMode ? "translate" : "auto_awesome") : "check_circle"
                            color: root.responseError ? Colours.palette.m3error : Colours.palette.m3outline
                            fontStyle: Tokens.font.icon.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: root.responseError ? Colours.palette.m3error : Colours.palette.m3outline
                            font: Tokens.font.label.large
                            text: {
                                if (root.localMode)
                                    return root.localError || Translator.translationLabel || qsTr("Translation, %1 to %2").arg(Translator.name(GlobalConfig.ai.translateFrom)).arg(Translator.name(GlobalConfig.ai.translateLanguage));
                                return root.waiting ? qsTr("Starting the local model...") : request.error || (request.status === "stopped" ? qsTr("Stopped. Partial response kept.") : request.status === "loading" ? qsTr("Generating...") : qsTr("AI response"));
                            }
                        }
                        // No amount is known while the runtime is prepared or
                        // the text translated, so it moves without claiming one.
                        StyledProgressBar {
                            Layout.preferredWidth: 72
                            visible: root.localMode && Translator.translating
                            indeterminate: true
                        }
                    }
                    StyledRect {
                        Layout.row: content.sideBySide ? 1 : 3
                        Layout.column: content.sideBySide ? 1 : 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: content.columnWidth
                        Layout.maximumWidth: content.columnWidth
                        Layout.preferredHeight: 360
                        visible: root.hasResponse
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHigh

                        // A plain Flickable rather than a ScrollView around a
                        // TextArea: nothing here chases a cursor, so the view
                        // stays where it is scrolled while the answer streams
                        // in, and follows the end only while already there.
                        StyledFlickable {
                            id: responseView

                            property bool follow: true
                            property bool scrolling

                            function toEnd(): void {
                                scrolling = true;
                                contentY = Math.max(0, contentHeight - height);
                                scrolling = false;
                            }

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            clip: true
                            contentWidth: width
                            contentHeight: responseColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            onContentYChanged: if (!scrolling)
                                follow = contentY >= contentHeight - height - 4
                            onContentHeightChanged: if (follow)
                                toEnd()

                            StyledScrollBar.vertical: StyledScrollBar {
                                flickable: responseView
                            }

                            Connections {
                                function onBusyChanged(): void {
                                    if (root.busy)
                                        responseView.follow = true;
                                }

                                target: root
                            }

                            Column {
                                id: responseColumn

                                width: responseView.width - Tokens.spacing.medium
                                spacing: Tokens.spacing.medium

                                Repeater {
                                    model: root.segments.length

                                    StyledRect {
                                        id: segment

                                        required property int index
                                        readonly property var part: root.segments[index] ?? { code: false, text: "" }

                                        width: responseColumn.width
                                        implicitHeight: body.implicitHeight + (part.code ? Tokens.padding.medium * 2 : 0)
                                        radius: Tokens.rounding.small
                                        color: part.code ? Colours.palette.m3surfaceContainerHighest : "transparent"

                                        TextEdit {
                                            id: body

                                            objectName: segment.index === 0 ? "aiResponse" : ""
                                            anchors.fill: parent
                                            anchors.margins: segment.part.code ? Tokens.padding.medium : 0
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: segment.part.code ? TextEdit.WrapAtWordBoundaryOrAnywhere : TextEdit.Wrap
                                            textFormat: segment.part.code ? TextEdit.PlainText : TextEdit.MarkdownText
                                            text: segment.part.text
                                            font.family: segment.part.code ? root.codeFamily : Tokens.font.mono.medium.family
                                            font.pointSize: segment.part.code ? root.codeSize : Tokens.font.mono.medium.pointSize
                                            color: Colours.palette.m3onSurface
                                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.3)
                                            selectedTextColor: Colours.palette.m3onSurface
                                            onSelectedTextChanged: root.responseSelection = selectedText
                                        }
                                    }
                                }
                            }
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
                        },
                        MenuItem {
                            text: qsTr("Code")
                            icon: "code"
                        }
                    ]
                }
                // With two or more languages installed, Translate picks from
                // them and runs offline; otherwise it asks the model, which
                // takes any language name.
                RowLayout {
                    id: languages

                    readonly property bool offline: Translator.installed.length >= 2

                    visible: root.actionIndex === 2
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    SplitButton {
                        id: fromLanguage

                        visible: languages.offline
                        Layout.alignment: Qt.AlignVCenter
                        type: SplitButton.Tonal
                        menuOnTop: true
                        menu.parent: root
                        menu.attachSideX: Menu.Left
                        menu.thisSideX: Menu.Left
                        stateLayer.onClicked: fromLanguage.expanded = !fromLanguage.expanded
                        menuItems: fromItems.instances
                        active: fromItems.instances.find(item => item.code === GlobalConfig.ai.translateFrom) ?? null
                        fallbackText: qsTr("From")
                        menu.onItemSelected: item => GlobalConfig.ai.translateFrom = item.code
                    }
                    MaterialIcon {
                        visible: languages.offline
                        text: "arrow_forward"
                        color: Colours.palette.m3outline
                    }
                    SplitButton {
                        id: toLanguage

                        visible: languages.offline
                        Layout.alignment: Qt.AlignVCenter
                        type: SplitButton.Tonal
                        menuOnTop: true
                        menu.parent: root
                        menu.attachSideX: Menu.Left
                        menu.thisSideX: Menu.Left
                        stateLayer.onClicked: toLanguage.expanded = !toLanguage.expanded
                        menuItems: toItems.instances
                        active: toItems.instances.find(item => item.code === GlobalConfig.ai.translateLanguage) ?? null
                        fallbackText: qsTr("To")
                        menu.onItemSelected: item => GlobalConfig.ai.translateLanguage = item.code
                    }
                    StyledTextField {
                        id: target

                        visible: !languages.offline
                        Layout.fillWidth: true
                        placeholderText: qsTr("Target language")
                        text: GlobalConfig.ai.translateLanguage
                        onEditingFinished: if (text !== GlobalConfig.ai.translateLanguage)
                            GlobalConfig.ai.translateLanguage = text
                    }
                    Item {
                        visible: languages.offline
                        Layout.fillWidth: true
                    }
                    IconButton {
                        type: IconButton.Text
                        icon: "language"
                        onClicked: root.showSettings = true
                    }
                }
                Variants {
                    id: fromItems

                    model: Translator.installed

                    MenuItem {
                        required property string modelData
                        readonly property string code: modelData

                        text: Translator.name(modelData)
                    }
                }
                Variants {
                    id: toItems

                    model: Translator.installed

                    MenuItem {
                        required property string modelData
                        readonly property string code: modelData

                        text: Translator.name(modelData)
                    }
                }
                StyledTextField {
                    id: custom

                    visible: root.actionIndex === 3
                    Layout.fillWidth: true
                    placeholderText: qsTr("What should the model do with this text?")
                }
                Item {
                    Layout.fillWidth: true
                    visible: root.actionIndex < 2 || root.actionIndex === 4
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
