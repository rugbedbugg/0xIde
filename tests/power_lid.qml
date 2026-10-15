//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
//@ pragma Env QML_XHR_ALLOW_FILE_READ=1
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.modules.nexus
import qs.modules.nexus.pages

// The Power page's lid rows over the real logind_lid.py, run with
// OX_LID_TEST_ROOT on a private root where tests/fixtures/fake-logind stands in
// for systemctl, busctl and sudo. Each choice goes through the helper as the
// page makes it; nothing reaches the real logind, and no lid event, suspend or
// hibernate can happen. The window is offscreen.
ShellRoot {
    id: h

    settings.watchFiles: false

    property var r: ({})
    readonly property var page: pageLoader.item
    property int at
    property real since: Date.now()
    readonly property string root: Quickshell.env("OX_LID_TEST_ROOT") ?? ""
    readonly property string dropin: root + "/etc/systemd/logind.conf.d/80-0xide-lid.conf"

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
    function select(label: string): var {
        return find(page, i => i.label === label && i.menuItems !== undefined && i.visible);
    }
    function info(label: string): var {
        return find(page, i => i.label === label && i.value !== undefined && i.menuItems === undefined && i.visible);
    }
    function texts(row: var): string {
        return row.menuItems.map(i => i.text).join("|");
    }
    // Chosen as the menu chooses: the signal, then the menu's own assignment.
    function choose(label: string, text: string): void {
        const row = select(label);
        const it = row.menuItems.find(i => i.text === text);
        row.selected(it);
        row.active = it;
    }
    function read(file: string): string {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + file, false);
        try {
            xhr.send();
            return xhr.status === 0 || xhr.status === 200 ? xhr.responseText : "";
        } catch (e) {
            return "";
        }
    }
    // A change to the private root, then a fresh read of it.
    function sh(script: string): void {
        shell.command = ["sh", "-c", script, "sh", root];
        shell.running = true;
    }

    readonly property string undocked: "When the lid is closed"
    readonly property string docked: "Closed with an external display"

    readonly property var steps: [
        [() => page !== null && page.lid !== null, () => {
            r.readsLogind = page.lid.ok === true && page.lid.undocked === "suspend" && page.lid.docked === "ignore";
            r.withoutHelperReadOnly = page.lidBlocked === "missing" && select(undocked) === null && select(docked) === null;
            r.withoutHelperShowsLogind = info(undocked)?.value === "Suspend" && info(docked)?.value === "Do nothing";
            r.withoutHelperSaysHow = (info(undocked)?.subtext ?? "").includes("./install --enable lid");
            sh('mkdir -p "$1/usr/local/libexec" && cp "' + page.lidScript + '" "$1/usr/local/libexec/0xide-logind-lid" && touch "$1/sudo-allowed"');
        }],
        [() => page.lidBlocked === "" && select(undocked) !== null, () => {
            r.offeredWithoutHibernate = texts(select(undocked)) === "Suspend|Do nothing|Lock screen" && texts(select(docked)) === "Suspend|Do nothing|Lock screen";
            r.showsWhatLogindDoes = select(undocked).active?.text === "Suspend" && select(docked).active?.text === "Do nothing";
            r.lookingWritesNothing = read(dropin) === "";
            choose(undocked, "Lock screen");
        }],
        [() => page.lid.undocked === "lock" && !page.lidApplying, () => {
            r.lockSet = page.lid.docked === "ignore" && page.lidError === "" && read(dropin).includes("HandleLidSwitch=lock\n")
                && read(dropin).includes("HandleLidSwitchExternalPower=lock\n") && read(dropin).includes("HandleLidSwitchDocked=ignore\n");
            r.menuShowsSet = select(undocked).active?.text === "Lock screen";
            choose(docked, "Suspend");
        }],
        [() => page.lid.docked === "suspend" && !page.lidApplying, () => {
            r.dockedSetKeepsUndocked = page.lid.undocked === "lock" && read(dropin).includes("HandleLidSwitchDocked=suspend\n");
            sh('touch "$1/reload-fails"');
        }],
        [() => !shell.running, () => choose(undocked, "Do nothing")],
        [() => page.lidError !== "" && !page.lidApplying, () => {
            r.failureSaidAndRolledBack = page.lidError.includes("the previous setting is back") && page.lid.undocked === "lock"
                && read(dropin).includes("HandleLidSwitch=lock\n") && info("The lid setting was not changed") !== null;
            r.menuShowsLogindAfterFailure = select(undocked).active?.text === "Lock screen";
            sh('rm -f "$1/reload-fails" && echo yes > "$1/can-hibernate"');
        }],
        [() => page.lid.hibernate === "yes", () => {
            r.hibernateWhereSupported = texts(select(undocked)) === "Suspend|Do nothing|Lock screen|Hibernate";
            sh('mkdir -p "$1/usr/lib/systemd/logind.conf.d" && printf "[Login]\\nHandleLidSwitchDocked=poweroff\\n" > "$1/usr/lib/systemd/logind.conf.d/90-vendor.conf" && "$1/usr/bin/systemctl" reload systemd-logind.service');
        }],
        [() => page.lidBlocked === "overridden", () => {
            r.overriddenReadOnly = select(undocked) === null && (info(undocked)?.subtext ?? "").includes("/usr/lib/systemd/logind.conf.d/90-vendor.conf");
            r.overriddenShowsWhatWins = info(docked)?.value === "Power off";
            sh('rm -f "$1/usr/lib/systemd/logind.conf.d/90-vendor.conf" "' + dropin + '" && mkdir -p "$1/run/systemd/logind.conf.d"'
                + ' && printf "[Login]\\nHandleLidSwitchExternalPower=ignore\\nHandleLidSwitchDocked=poweroff\\n" > "$1/run/systemd/logind.conf.d/10-local.conf"'
                + ' && printf \'[["handle-lid-switch","Dock app","Docked mode","block",1000,7]]\' > "$1/inhibitors.json"'
                + ' && "$1/usr/bin/systemctl" reload systemd-logind.service');
        }],
        [() => page.lidBlocked === "" && page.lid.docked === "poweroff", () => {
            r.elsewhereShownNotOffered = select(docked).active?.text === "Power off (set elsewhere)"
                && texts(select(docked)) === "Suspend|Do nothing|Lock screen|Hibernate|Power off (set elsewhere)";
            r.inhibitorNamed = (info("Closing the lid is handled elsewhere for now")?.subtext ?? "").includes("Dock app: Docked mode");
            r.chargerSaidInRow = select(undocked).subtext === "On a charger it is Do nothing, set elsewhere; a change here sets both";
            choose(docked, "Power off (set elsewhere)");
        }],
        [() => !page.lidApplying, () => {
            r.elsewhereCannotBeChosen = read(dropin) === "" && page.lid.docked === "poweroff";
            choose(undocked, "Suspend");
        }],
        // Undocked was already suspend: wait for the read that follows the change.
        [() => read(dropin) !== "" && !page.lidApplying && page.lid.docked !== "poweroff", () => {
            r.otherFallsBackToDefault = page.lid.docked === "ignore" && read(dropin).includes("HandleLidSwitchDocked=ignore\n");
            r.noErrorLeft = page.lidError === "";
            r.chargerRowBackOnceBothSet = select(undocked).subtext === "On battery and on a charger";
            r.noNotesUnderSections = find(page, i => typeof i.text === "string" && (i.text.includes("keep their own timers") || i.text.includes("systemd-logind acts on this"))) === null;
        }],
    ]

    NexusState {
        id: testState
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 1200

        Loader {
            id: pageLoader

            anchors.fill: parent
            active: false

            // No sudo here: the helper in test mode writes the private root.
            sourceComponent: PowerPage {
                nState: testState
                lidWriter: ["/usr/bin/python3", "-I", lidScript]
            }
        }
    }

    Timer {
        interval: 200
        running: true
        onTriggered: pageLoader.active = true
    }

    Process {
        id: shell

        onExited: h.page.refreshLid()
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
