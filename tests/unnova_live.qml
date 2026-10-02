//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Services
import qs.components
import qs.services
import qs.modules.unnova
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
            UnNova.open();
            check("single surface", UnNova.window === originalWindow);
            childKey = Processes.usage(child.processId).key;
            stubbornKey = Processes.usage(stubborn.processId).key;
            search("sleep 3017");
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
        } else if (n === 77) {
            UnNova.close();
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
            UnNova.window.visible = false;
        } else if (n === 119) {
            check("hide stops sampling", !UnNova.isOpen && !Processes.active);
            console.log("RESULTS " + JSON.stringify(results));
            console.log("COSTS " + JSON.stringify(costs));
            Qt.quit();
        }
    }
}
