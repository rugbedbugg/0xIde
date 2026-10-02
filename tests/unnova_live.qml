//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Caelestia.Services
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.unnova
import qs.modules.nexus as Nexus
import qs.modules.dashboard as Dashboard
import qs.modules.session as Session
import "modules/unnova/unnova.js" as U

ShellRoot {
    id: test
    settings.watchFiles: false
    property var results: ({})
    property var originalWindow
    property string childKey
    property string stubbornKey
    property int stoppedAt
    property var costs: []
    property var infoPane
    property var closeButton
    property var nexusWindow
    property bool nexusClosed: false
    property var referenceTabs
    TestEvent { id: input }
    Component {
        id: dashboardTabsReference
        Dashboard.Tabs {
            visible: false
            height: implicitHeight
            nonAnimWidth: width
            screenState: ScreenState {
                modelData: Quickshell.screens[0]
                dashboardTab: 1
            }
        }
    }
    Component {
        id: nexusComponent
        FloatingWindow {
            implicitWidth: 960
            implicitHeight: 600
            color: Colours.tPalette.m3surface
            contentItem.Tokens.screen: screen.name
            contentItem.Config.screen: screen.name
            Nexus.Nexus {
                anchors.fill: parent
                nState.screen: Quickshell.screens[0]
                nState.isWindow: true
                nState.currentPageIdx: 12
                onClose: { test.nexusClosed = true; test.nexusWindow.destroy(); }
            }
        }
    }
    property int stage: 0
    Process { id: child; command: ["sleep", "3017"]; running: true }
    Process { id: stubborn; command: ["bash", "-c", "trap '' TERM; exec sleep 3019"]; running: true }
    Component.onDestruction: {
        if (child.running) child.signal(9);
        if (stubborn.running) stubborn.signal(9);
    }
    ScreenState { id: state; modelData: Quickshell.screens[0]; session: true }
    FloatingWindow {
        id: launcherWindow
        title: "UnNova launcher verification"
        implicitWidth: 140
        implicitHeight: 720
        visible: state.session
        Session.Content { id: panel; screenState: state }
    }
    function descendants(obj) {
        let out = [];
        for (const c of obj.children ?? []) {
            out.push(c);
            out = out.concat(descendants(c));
        }
        return out;
    }
    function find(predicate) { return descendants(UnNova.window.contentItem).find(predicate); }
    function tabGeometry(tabs) {
        const bar = descendants(tabs).find(o => o.contentModel !== undefined && o.currentIndex !== undefined);
        const icon = descendants(bar.currentItem).find(o => o.text === "list_alt");
        const label = descendants(bar.currentItem).find(o => o.text === "Processes" && o.elide !== undefined);
        const indicator = tabs.children.find(o => o.clip && o.implicitHeight === 3);
        const divider = tabs.children.find(o => o.implicitHeight === 1);
        return {
            bandHeight: tabs.height, barTop: bar.y, barHeight: bar.height,
            iconSize: [icon.width, icon.height], iconLabelGap: label.y - icon.y - icon.height,
            labelBaseline: label.mapToItem(tabs, 0, label.baselineOffset).y,
            underline: [indicator.x, indicator.y, indicator.width, indicator.height],
            divider: [divider.y, divider.height]
        };
    }
    function search(text) {
        find(o => o.placeholderText === "Search by name, PID, command or user").text = text;
        check("search field drives model", Processes.query === text);
    }
    function rowIndex(key) {
        for (let i = 0; i < Processes.model.rowCount(); ++i)
            if (Processes.model.data(Processes.model.index(i, 0), 257) === key) return i;
        return -1;
    }
    function click(text) {
        const b = find(o => o.text === text && o.clicked !== undefined && o.visible && !o.disabled);
        if (!b) throw new Error("Missing enabled button: " + text);
        b.clicked();
    }
    function check(name, value) {
        results[name] = !!value;
        console.log((value ? "PASS " : "FAIL ") + name);
    }
    function snapshot(name) {
        find(o => o.currentTab !== undefined).grabToImage(result => result.saveToFile(Quickshell.env("UNNOVA_TEST_OUTPUT") + "/" + name + ".png"));
    }
    function phase(name) {
        console.log("PHASE " + JSON.stringify({name: name, pid: Quickshell.processId, samples: Processes.samples, count: Processes.count}));
    }
    Connections {
        target: Processes
        function onSampled() { test.costs.push(Processes.sampleMs); }
    }
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            test.stage++;
            try { test.advance(test.stage); }
            catch (e) { console.log("FAIL stage " + test.stage + ": " + e); }
        }
    }
    function advance(n) {
        if (n === 2) {
            check("closed is idle", !Processes.active);
            const launch = descendants(panel).find(o => o.activeFocusOnTab && o.manualHoverOverride !== undefined);
            check("launcher keyboard focus", !!launch);
            launch.clicked(null);
        } else if (n === 5) {
            check("launcher opens and closes power panel", UnNova.isOpen && !state.session);
            originalWindow = UnNova.window;
            const content = find(o => o.currentTab !== undefined);
            const tabs = find(o => o.tabs?.length === 2);
            check("responsive preferred size", originalWindow.width === originalWindow.sizing.width.preferred && originalWindow.height === originalWindow.sizing.height.preferred);
            check("header has no branding", !descendants(content).some(o => o.text === "UnNova" || o.text === "monitoring"));
            const chrome = find(o => o.cornerWidth !== undefined);
            check("navigation clears close pocket", tabs.mapToItem(content, tabs.width, 0).x <= content.width - chrome.cornerWidth - content.Tokens.spacing.large);
            check("divider confined to tabs", tabs.width < content.width * 0.6 && tabs.x > 0);
            check("header has room for Nexus title", tabs.parent.height === tabs.height + content.Tokens.padding.large);
            check("one header close control", descendants(content).filter(o => o.icon === "close" && o.clicked !== undefined && o.mapToItem(content, 0, 0).y < tabs.y + tabs.height).length === 1);
            referenceTabs = dashboardTabsReference.createObject(content, { width: tabs.width, tabs: tabs.tabs });

            UnNova.open();
            check("single surface", UnNova.window === originalWindow);
            childKey = Processes.usage(child.processId).key;
            stubbornKey = Processes.usage(stubborn.processId).key;
            search("sleep 3017");
        } else if (n === 6) {
            const content = find(o => o.currentTab !== undefined);
            const tabs = find(o => o.tabs?.length === 2);
            const geometry = tabGeometry(tabs);
            check("navigation exactly matches Dashboard geometry", JSON.stringify(geometry) === JSON.stringify(tabGeometry(referenceTabs)));
            const strip = find(o => o.compact !== undefined);
            const gap = strip.mapToItem(content, 0, 0).y - tabs.mapToItem(content, 0, tabs.height).y;
            const artwork = descendants(strip);
            check("CPU uses Performance usage artwork", artwork.some(o => o.usage !== undefined && o.shape !== undefined && o.implicitSize === 44));
            check("resource gauges use Performance arcs", artwork.filter(o => o.startAngle === -225 && o.sweepAngle === 270).length === 2);
            check("process summary excludes device storage", !artwork.some(o => o.text === "Storage" || o.icon === "hard_drive"));
            check("one normal padding below navigation divider", gap === content.Tokens.padding.large && geometry.divider[0] + geometry.divider[1] === tabs.height);
            check("navigation uses Dashboard outer top padding", tabs.parent.y === Math.max(0, content.Tokens.padding.large - content.Config.border.thickness));
            console.log("NAVIGATION " + JSON.stringify({ geometry: geometry, top: tabs.y, contentGap: gap }));
            const bar = descendants(tabs).find(o => o.contentModel !== undefined && o.currentIndex !== undefined);
            for (const index of [0, 1]) {
                const tab = bar.itemAt(index);
                input.mouseClick(tab, tab.width / 2, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                check("native navigation selects tab " + index, content.currentTab === index);
                const heading = tabs.parent.children.find(o => o.elide !== undefined);
                check("Nexus title follows tab " + index, heading.text === tabs.tabs[index].text && heading.font.pixelSize === content.Tokens.font.title.large.pixelSize && heading.x + heading.width < tabs.x);
            }
            check("navigation selection is independent of Dashboard", referenceTabs.screenState.dashboardTab === 1);
            referenceTabs.destroy();
        } else if (n === 7) {
            const row = find(o => o.key === childKey && o.selected !== undefined);
            row.children.find(o => o.containsMouse !== undefined).clicked(null);
            check("row click selects", Processes.selectedKey === childKey);
            check("selected identity", Processes.selected.pid === child.processId && Processes.selected.command.endsWith("sleep 3017"));
            infoPane = find(o => o.pendingKey !== undefined && o.choose !== undefined);
            snapshot("selected");
        } else if (n === 8) {
            click("Tree");
            search("");
            const list = find(o => o.reuseItems !== undefined && o.model === Processes.model);
            list.positionViewAtIndex(rowIndex(Processes.selected.parentKey), ListView.Center);
        } else if (n === 9) {
            const parent = find(o => o.key === Processes.selected.parentKey && o.selected !== undefined);
            const chevron = descendants(parent).find(o => o.icon === "chevron_right");
            chevron.clicked();
            check("chevron folds without selecting", rowIndex(childKey) === -1 && Processes.selectedKey === childKey);
            chevron.clicked();
            check("chevron expands without selecting", rowIndex(childKey) >= 0 && Processes.selectedKey === childKey);
            snapshot("tree");
        } else if (n === 10) {
            search("sleep 3017");
            click("List");
            click("Memory");
            const menu = find(o => o.items && o.items.length === 4);
            check("sort menu opens", menu.expanded);
            menu.items.find(o => o.key === "pid").clicked();
            menu.expanded = false;
            check("sort menu selects PID", Processes.sortKey === "pid");
            Processes.sortKey = "memory";
            click("End task");
            check("TERM confirmation", infoPane.mode === "confirm" && infoPane.pending.signal === "TERM");
            click("End task");
        } else if (n === 13) {
            check("TERM exits disposable child", !Processes.isAlive(childKey) && !child.running);
            check("unrelated child untouched", Processes.isAlive(stubbornKey));
            search("sleep 3019");
            Processes.selectedKey = stubbornKey;
            infoPane.choose(U.action("pause"));
            click("Pause");
        } else if (n === 16) {
            check("STOP pauses disposable child", Processes.selected.state === "T");
            infoPane.choose(U.action("resume"));
            click("Resume");
        } else if (n === 19) {
            check("CONT resumes disposable child", Processes.selected.state !== "T");
            click("End task");
            click("End task");
        } else if (n === 29) {
            check("TERM never escalates", Processes.isAlive(stubbornKey) && infoPane.mode === "stuck");
            snapshot("force-confirmation");
            click("Keep waiting");
            check("keep waiting remains alive", Processes.isAlive(stubbornKey));
        } else if (n === 39) {
            click("Force stop");
        } else if (n === 43) {
            check("explicit KILL exits disposable child", !Processes.isAlive(stubbornKey) && !stubborn.running);
            Processes.query = "";
            Processes.selectedKey = "";
            snapshot("list");
            phase("visible-start");
        } else if (n === 73) {
            phase("visible-end");
            const tab = find(o => o.currentTab !== undefined);
            tab.currentTab = 0;
            check("BitNet state agrees", !AiRuntime.serving && U.aiState({serving: AiRuntime.serving, installed: AiRuntime.info.installed}) !== "Ready");
        } else if (n === 75) {
            snapshot("oxide");
            const ai = find(o => o.title === "Local AI" && o.lines !== undefined);
            const dictation = find(o => o.title === "Dictation" && o.lines !== undefined);
            const translation = find(o => o.title === "Translation" && o.lines !== undefined);
            check("AI card spans service grid", ai.width === ai.parent.width && ai.parent.columns === 2);
            check("service cards provide useful details", ai.lines.some(l => l.includes("Context window")) && dictation.lines.some(l => l.startsWith("Language:")) && translation.lines.some(l => l.startsWith("Selected:")));
            check("on-demand cards remain informational", !descendants(dictation).some(o => o.clicked !== undefined) && !descendants(translation).some(o => o.clicked !== undefined));
        } else if (n === 77) {
            closeButton = find(o => o.icon === "close" && o.clicked !== undefined);
            input.mouseMove(closeButton, closeButton.width / 2, closeButton.height / 2, 0, Qt.NoButton, Qt.NoModifier);
        } else if (n === 78) {
            check("corner hover feedback", closeButton.hovered && closeButton.inactiveOnColour === Colours.palette.m3error);
            snapshot("close-hover");
            input.mousePress(closeButton, closeButton.width / 2, closeButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
        } else if (n === 79) {
            check("corner pressed feedback", closeButton.pressed && Math.abs(closeButton.label.scale - 0.8) < 0.01);
            snapshot("close-pressed");
            input.mouseRelease(closeButton, closeButton.width / 2, closeButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
        } else if (n === 81) {
            check("close stops sampling", !UnNova.isOpen && !Processes.active);
            stoppedAt = Processes.samples;
            phase("hidden-start");
        } else if (n === 111) {
            phase("hidden-end");
            check("hidden stays idle", Processes.samples === stoppedAt);
            UnNova.open();
            check("reopen samples immediately", Processes.samples === stoppedAt + 1);
        } else if (n === 115) {
            check("reopen single surface", UnNova.isOpen && Processes.active);
            check("reopen selects Processes", find(o => o.currentTab !== undefined).currentTab === 1);
            // Constrain only this disposable window; implicit size changes
            // alone do not resize an already mapped Wayland surface.
            UnNova.window.maximumSize.width = 960;
            UnNova.window.maximumSize.height = 600;
            Processes.selectedKey = Processes.usage(Quickshell.processId).key;
        } else if (n === 119) {
            check("small compositor size", UnNova.window.width === 960 && UnNova.window.height === 600);
            snapshot("small-selected");
            const info = find(o => o.pendingKey !== undefined && o.choose !== undefined);
            const list = find(o => o.reuseItems !== undefined && o.model === Processes.model);
            const search = find(o => o.placeholderText === "Search by name, PID, command or user");
            console.log("LAYOUT " + JSON.stringify({ inspector: info.width, listWidth: list.width, listHeight: list.height, search: search.width }));
            check("small surface retains useful panes", info.width >= 260 && list.width >= 600 && list.height >= 200 && search.width > 180);
            const strip = find(o => o.compact !== undefined);
            check("compact resource labels stay inside", strip.compact && descendants(strip).filter(o => o.text !== undefined && o.visible).every(o => o.mapToItem(strip, 0, 0).x >= 0 && o.mapToItem(strip, o.width, o.height).x <= strip.width));
            const scroll = descendants(info).find(o => o.contentHeight !== undefined && o.flickableDirection !== undefined);
            check("inspector retains scrolling", scroll && scroll.contentHeight > scroll.height);
        } else if (n === 120) {
            UnNova.window.visible = false;
        } else if (n === 121) {
            check("hide stops sampling", !UnNova.isOpen && !Processes.active);
            nexusWindow = nexusComponent.createObject(test);
        } else if (n === 127) {
            nexusWindow.contentItem.children.find(o => o.nState !== undefined).grabToImage(result => result.saveToFile(Quickshell.env("UNNOVA_TEST_OUTPUT") + "/nexus.png"));
            closeButton = descendants(nexusWindow.contentItem).find(o => o.icon === "close" && o.clicked !== undefined);
            check("Nexus uses shared chrome", closeButton.parent.leftInset > 100 && closeButton.parent.isWindow);
            input.mouseMove(closeButton, closeButton.width / 2, closeButton.height / 2, 0, Qt.NoButton, Qt.NoModifier);
        } else if (n === 128) {
            input.mouseMove(closeButton, closeButton.width / 2, closeButton.height / 2, 0, Qt.NoButton, Qt.NoModifier);
            check("Nexus corner hover unchanged", closeButton.hovered && closeButton.inactiveOnColour === Colours.palette.m3error);
            input.mousePress(closeButton, closeButton.width / 2, closeButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
        } else if (n === 129) {
            check("Nexus corner press unchanged", closeButton.pressed && Math.abs(closeButton.label.scale - 0.8) < 0.01);
            input.mouseRelease(closeButton, closeButton.width / 2, closeButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
        } else if (n === 131) {
            check("Nexus close unchanged", nexusClosed);
            check("Nexus does not sample processes", !Processes.active);
            console.log("RESULTS " + JSON.stringify(results));
            console.log("COSTS " + JSON.stringify(costs));
            Qt.quit();
        }
    }
}
