//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.modules.unnova

// Actual controls with inert service substitutes. The window is never mapped.
// The runner also blocks uv so a default service cannot escape these mocks.
ShellRoot {
    id: test
    settings.watchFiles: false
    property var results: ({})
    property var calls: []
    function record(name) { calls = [...calls, name]; }
    function check(name, value) {
        results[name] = !!value;
        if (!value) console.log("FAIL " + name);
    }
    function descendants(o) {
        return (o.children ?? []).reduce((a, c) => a.concat([c], descendants(c)), []);
    }
    function named(name) { return descendants(win.contentItem).find(o => o.objectName === name); }
    QtObject {
        id: ai
        property var info: ({installed: true})
        property bool serving: false
        property bool stopping: false
        property bool installing: false
        property string operation: "install"
        property string endpoint: ""
        function start() { test.record("start"); }
        function cancel() { test.record("cancelInstall"); }
        function stop() { test.record("stop"); }
        function restart() { test.record("restart"); }
    }
    QtObject {
        id: translation
        property bool translating: false
        function cancel() { test.record("cancel"); }
    }
    FloatingWindow {
        id: win
        visible: false
        implicitWidth: 640
        implicitHeight: 200
        contentItem.Tokens.screen: screen.name
        contentItem.Config.screen: screen.name
        RowLayout {
            anchors.fill: parent
            AiControls { runtime: ai }
            TranslationAction { translator: translation }
        }
    }
    Timer {
        interval: 500
        running: true
        onTriggered: {
            try {
                const start = named("aiStart"), unload = named("aiUnload"), restart = named("aiRestart"),
                      cancelAi = named("aiCancel"), cancel = named("translationCancel");
                const shown = () => [start, unload, restart, cancelAi].filter(b => b.visible).map(b => b.objectName).join();
                check("opening controls starts no work", calls.length === 0);
                check("installed stopped AI offers only Start", shown() === "aiStart");
                start.clicked();
                check("Start delegates once to existing runtime", calls.join() === "start");
                ai.serving = true;
                check("starting server offers Unload but not Restart", shown() === "aiUnload");
                restart.clicked();
                check("Restart is rejected before endpoint ready", calls.length === 1);
                unload.clicked();
                check("Unload delegates while starting", calls.join() === "start,stop");
                ai.endpoint = "http://test";
                check("a ready server offers Unload and Restart", shown() === "aiUnload,aiRestart");
                restart.clicked();
                check("ready server Restart delegates", calls.join() === "start,stop,restart");
                ai.stopping = true;
                unload.clicked(); restart.clicked();
                check("stopping offers nothing and rejects stale clicks", shown() === "" && calls.length === 3);
                ai.stopping = false; ai.installing = true;
                start.clicked(); unload.clicked(); restart.clicked();
                check("installing offers only Cancel and rejects runtime clicks", shown() === "aiCancel" && calls.length === 3);
                cancelAi.clicked();
                check("Cancel installation delegates once", calls.join() === "start,stop,restart,cancelInstall");
                ai.serving = false; ai.endpoint = "";
                start.clicked();
                check("installing model cannot start server", calls.length === 4);
                ai.installing = false; ai.info = {installed: false};
                start.clicked();
                check("missing model offers nothing and cannot start", shown() === "" && calls.length === 4);
                ai.info = {};
                start.clicked();
                check("unknown installation offers nothing", shown() === "" && calls.length === 4);
                ai.info = {installed: true};
                check("Start returns once installation is known", shown() === "aiStart");
                cancel.clicked();
                check("idle translation shows no cancel and rejects a click", !cancel.visible && calls.length === 4);
                translation.translating = true;
                cancel.clicked();
                check("active translation cancellation is shown and delegates once", cancel.visible && calls.join() === "start,stop,restart,cancelInstall,cancel");
                translation.translating = false;
                cancel.clicked();
                check("finished translation hides cancel and rejects stale cancellation", !cancel.visible && calls.length === 5);
                console.log("RESULTS " + JSON.stringify(results));
            } catch (e) {
                console.log("FAIL " + e);
                console.log("RESULTS " + JSON.stringify(Object.assign({}, results, {completed: false})));
            }
            Qt.quit();
        }
    }
}
