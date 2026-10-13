//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
//@ pragma Env QML_XHR_ALLOW_FILE_READ=1
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.modules.nexus
import qs.modules.nexus.pages
import "modules/nexus/pages/power/sleepPolicy.js" as P

// The Power page on private settings: each choice as the menu makes it, what
// reaches shell.json, and what a live list bound like IdleMonitors' sees. No
// IdleMonitor exists here, so nothing can lock, blank or suspend; the window
// is offscreen.
ShellRoot {
    id: h

    settings.watchFiles: false

    property var r: ({})
    readonly property var page: pageLoader.item
    property int at
    property real since: Date.now()
    readonly property string config: "@CONFIG@"

    function find(item: Item, test: var): var {
        if (test(item))
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = find(item.children[i], test);
            if (found)
                return found;
        }
        return null;
    }
    function row(): var {
        return find(page, i => i.label === "Sleep after inactivity" && i.menuItems !== undefined);
    }
    function item(text: string): var {
        return page.sleepItems.find(i => i.text === text);
    }
    // Chosen as the menu chooses: the signal, then the menu's own assignment.
    function choose(text: string): void {
        const it = item(text);
        row().selected(it);
        row().active = it;
    }
    // Read afresh each time: the file is replaced, not rewritten in place.
    function saved(): var {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + config, false);
        try {
            xhr.send();
            return JSON.parse(xhr.responseText).general?.idle?.timeouts ?? null;
        } catch (e) {
            return null;
        }
    }
    function canon(v: var): string {
        return JSON.stringify(P.canonical(P.copy(v)));
    }
    function live(): var {
        return mirror.instances.map(i => i.modelData);
    }
    function sleepEntry(list: var): var {
        return (list ?? []).find(e => JSON.stringify(e.idleAction).includes("uspend")) ?? null;
    }
    function others(list: var): string {
        return canon((list ?? []).filter(e => !JSON.stringify(e.idleAction).includes("uspend")));
    }
    function writeConfig(json: string): void {
        writer.command = ["sh", "-c", 'printf "%s" "$1" > "$2.new" && mv -f "$2.new" "$2"', "sh", json, config];
        writer.running = true;
    }
    readonly property string upstreamOthers: canon([
        { timeout: 180, idleAction: "lock" },
        { timeout: 300, idleAction: "dpms off", returnAction: "dpms on" }
    ])

    readonly property var steps: [
        [() => page !== null && page.activeItem !== null, () => {
            r.opensOnUpstreamDefault = page.activeItem.text === "10 min" && row().active === page.activeItem;
            r.lookingWritesNothing = saved() === null;
            choose("30 min");
        }],
        [() => sleepEntry(saved())?.timeout === 1800, () => {
            r.presetPersists = sleepEntry(saved()).enabled === undefined;
            // The documented cost: the whole list is written, so upstream's
            // lock and display-off entries now sit in shell.json as well.
            r.otherEntriesMaterialisedUnchanged = others(saved()) === upstreamOthers;
            r.liveListFollows = sleepEntry(live())?.timeout === 1800 && others(live()) === upstreamOthers;
            r.menuShowsConfigured = page.activeItem.text === "30 min";
            choose("Never");
        }],
        [() => sleepEntry(saved())?.enabled === false, () => {
            r.neverKeepsLockAndDisplayOff = others(saved()) === upstreamOthers && sleepEntry(saved()).timeout === 1800;
            r.neverLive = sleepEntry(live())?.enabled === false;
            r.neverShown = page.activeItem.text === "Never" && row().active === page.activeItem;
            choose("1 h");
        }],
        [() => sleepEntry(saved())?.timeout === 3600, () => {
            r.neverThenDurationReenables = sleepEntry(saved()).enabled === undefined && others(saved()) === upstreamOthers;
            choose("Custom…");
        }],
        [() => page.customOpen, () => {
            const picker = find(page, i => i.picked !== undefined && i.minutePart !== undefined);
            r.customOpensOnCurrent = picker.minutes === 60;
            r.customCannotBeZero = (() => {
                picker.set(0);
                const apply = find(page, i => i.text === "Apply");
                const refused = apply.disabled;
                picker.set(95);
                return refused && !apply.disabled;
            })();
            r.customStepsOfFive = picker.minutes === 95;
            find(page, i => i.text === "Apply").clicked();
        }],
        [() => sleepEntry(saved())?.timeout === 5700, () => {
            r.customPersists = !page.customOpen && others(saved()) === upstreamOthers;
            r.customShown = page.activeItem.text === "Custom…" && page.activeItem.activeText === "1 h 35 min";
            // Edited outside Nexus: the page follows without writing back.
            writeConfig(JSON.stringify({ general: { idle: { timeouts: [
                { timeout: 120, idleAction: ["notify-send", "Idle"] },
                { timeout: 900, idleAction: "exec systemctl suspend", note: "mine" }
            ] } } }));
        }],
        [() => page.activeItem?.text === "15 min", () => {
            r.externalEditIsLive = sleepEntry(live())?.timeout === 900;
            choose("5 min");
        }],
        [() => sleepEntry(saved())?.timeout === 300, () => {
            r.customActionKept = canon(saved()) === canon([
                { timeout: 120, idleAction: ["notify-send", "Idle"] },
                { timeout: 300, idleAction: "exec systemctl suspend", note: "mine" }
            ]);
            writeConfig(JSON.stringify({ general: { idle: { timeouts: [
                { timeout: 600, idleAction: ["suspend"] },
                { timeout: 3600, idleAction: ["systemctl", "suspend"] }
            ] } } }));
        }],
        [() => page.policy.state === "multiple", () => {
            r.ambiguousHidesTheRow = !row().visible && !!find(page, i => i.icon === "warning" && i.visible);
            page.sleepAfter(5);
            page.never();
        }],
        // Past the 500 ms save debounce, so a write would have landed.
        [() => Date.now() - h.since > 1500, () => {
            r.ambiguousIsNeverChanged = canon(saved()) === canon([
                { timeout: 600, idleAction: ["suspend"] },
                { timeout: 3600, idleAction: ["systemctl", "suspend"] }
            ]);
            writeConfig(JSON.stringify({ general: { idle: { timeouts: [
                { timeout: 180, idleAction: "lock" }
            ] } } }));
        }],
        [() => page.policy.state === "none", () => {
            r.noSleepEntryReadsNever = page.activeItem.text === "Never";
            choose("2 h");
        }],
        [() => sleepEntry(saved())?.timeout === 7200, () => {
            r.durationAddsUpstreamAction = canon(saved()) === canon([
                { timeout: 180, idleAction: "lock" },
                { timeout: 7200, idleAction: ["suspendThenHibernate"] }
            ]);
            choose("Never");
        }],
        [() => sleepEntry(saved())?.enabled === false, () => {
            r.addedEntryCanBeTurnedOff = others(saved()) === canon([{ timeout: 180, idleAction: "lock" }]);
        }],
    ]

    NexusState {
        id: testState
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 900

        // Loaded into a window that exists, as Pages.qml loads a page.
        Loader {
            id: pageLoader

            anchors.fill: parent
            active: false

            sourceComponent: PowerPage {
                nState: testState
            }
        }
    }

    Timer {
        interval: 200
        running: true
        onTriggered: pageLoader.active = true
    }

    // As modules/IdleMonitors.qml binds it, without the monitors.
    Variants {
        id: mirror

        model: GlobalConfig.general.idle.timeouts

        QtObject {
            required property var modelData
        }
    }

    Process {
        id: writer
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (h.at >= h.steps.length) {
                console.log("RESULT " + JSON.stringify(h.r));
                Qt.quit();
                return;
            }
            const [ready, act] = h.steps[h.at];
            let ok = false;
            try {
                ok = ready();
            } catch (e) {}
            if (ok) {
                act();
                h.at++;
                h.since = Date.now();
            } else if (Date.now() - h.since > 8000) {
                h.r["timeoutAtStep" + h.at] = false;
                console.log("RESULT " + JSON.stringify(h.r));
                Qt.quit();
            }
        }
    }
}
