//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import Quickshell
import "modules/nexus/pages/power/sleepPolicy.js" as P

// The sleep entry of general.idle.timeouts as the Power page reads and
// rewrites it, on lists written out here. Nothing is configured or run.
ShellRoot {
    settings.watchFiles: false

    readonly property var upstream: [
        { timeout: 180, idleAction: "lock" },
        { timeout: 300, idleAction: "dpms off", returnAction: "dpms on" },
        { timeout: 600, idleAction: ["suspendThenHibernate"] }
    ]

    function eq(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    Component.onCompleted: {
        const r = {};
        const up = upstream;

        // What counts as sleep, as IdleMonitors would run it.
        r.sleepActions = [["suspendThenHibernate"], ["suspend"], ["systemctl", "suspend"], ["loginctl", "suspend-then-hibernate"],
            ["systemctl", "hybrid-sleep"], "exec systemctl suspend", "exec  loginctl   suspend"].every(a => P.isSleepAction(a));
        r.otherActions = !["lock", "dpms off", ["hibernate"], ["systemctl", "hibernate"], ["poweroff"], ["notify-send", "suspend"],
            "exec notify-send suspend", "suspend", null, 7, {}].some(a => P.isSleepAction(a));

        // Upstream's own list.
        const c = P.classify(up);
        r.upstreamIsSingle = c.state === "single" && c.index === 2 && c.seconds === 600;

        const thirty = P.withSleepAfter(up, 1800);
        r.durationChangesOnlyTimeout = eq(thirty, [up[0], up[1], { timeout: 1800, idleAction: ["suspendThenHibernate"] }]);
        r.inputUntouched = eq(up, [
            { timeout: 180, idleAction: "lock" },
            { timeout: 300, idleAction: "dpms off", returnAction: "dpms on" },
            { timeout: 600, idleAction: ["suspendThenHibernate"] }
        ]);

        const never = P.withNever(up);
        r.neverDisablesOnlySleep = eq(never, [up[0], up[1], { timeout: 600, idleAction: ["suspendThenHibernate"], enabled: false }]);
        r.neverReadsAsZero = P.classify(never).state === "single" && P.classify(never).seconds === 0;

        const back = P.withSleepAfter(never, 3600);
        r.neverThenDurationReenables = eq(back, [up[0], up[1], { timeout: 3600, idleAction: ["suspendThenHibernate"] }]);
        r.neverTwiceIsSame = P.same(P.withNever(never), never);
        r.sameDurationIsSame = P.same(P.withSleepAfter(up, 600), up);

        // A custom entry keeps its action and every field it has.
        const custom = [
            { timeout: 120, idleAction: ["notify-send", "Idle"], returnAction: ["notify-send", "Back"] },
            { timeout: 240, idleAction: "lock", inhibitWhenAudio: false },
            { timeout: 900, idleAction: "exec systemctl suspend", respectInhibitors: true, inhibitWhenCharging: true, note: "mine" }
        ];
        const custom45 = P.withSleepAfter(custom, 2700);
        r.customKeepsFields = eq(custom45, [custom[0], custom[1],
            { timeout: 2700, idleAction: "exec systemctl suspend", respectInhibitors: true, inhibitWhenCharging: true, note: "mine" }]);
        r.customNeverKeepsFields = eq(P.withNever(custom)[2],
            { timeout: 900, idleAction: "exec systemctl suspend", respectInhibitors: true, inhibitWhenCharging: true, note: "mine", enabled: false });

        // No sleep entry: never already; a duration adds upstream's action.
        const none = [up[0], up[1], { timeout: 7200, idleAction: ["hibernate"] }];
        r.noneIsNever = P.classify(none).state === "none" && P.classify(none).seconds === 0;
        r.noneNeverChangesNothing = P.same(P.withNever(none), none);
        r.noneDurationAppends = eq(P.withSleepAfter(none, 300), [...none, { timeout: 300, idleAction: ["suspendThenHibernate"] }]);
        r.emptyDurationAppends = eq(P.withSleepAfter([], 300), [{ timeout: 300, idleAction: ["suspendThenHibernate"] }]);

        // Two sleep entries: which is meant is not clear, so nothing changes.
        const two = [...up, { timeout: 3600, idleAction: ["systemctl", "suspend"] }];
        r.multipleIsAmbiguous = P.classify(two).state === "multiple";
        r.multipleRefusesDuration = P.withSleepAfter(two, 300) === null;
        r.multipleRefusesNever = P.withNever(two) === null;
        const twoOneOff = [...up, { timeout: 3600, idleAction: ["suspend"], enabled: false }];
        r.disabledSecondStillAmbiguous = P.classify(twoOneOff).state === "multiple";

        r.zeroRefused = P.withSleepAfter(up, 0) === null && P.withSleepAfter(up, -60) === null;

        console.log("RESULT " + JSON.stringify(r));
        Qt.quit();
    }
}
